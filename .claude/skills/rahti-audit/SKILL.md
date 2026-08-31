---
name: rahti-audit
description: Auditoi nopeasti KAIKKI CSC Rahti 2 -sovellukset yhdellä ajolla — deploymentit, podit, routet ja niiden HTTP-vasteet, warning-eventit ja kiintiöt jokaisesta namespacesta johon tunnuksella on pääsy. Käytä kun käyttäjä haluaa tarkistaa ovatko Rahti-sovellukset pystyssä, auditoida tuotannon, katsoa onko podeissa restartteja tai crashloopeja, varmistaa että routet vastaavat, tai kysyy näkyykö Rahtissa mitään hälyttävää. Triggeröi myös pelkästä "auditoi Rahti", "onko tuotanto kunnossa", "onko OpenShiftissä virheitä", "crashloop", "onko podit pystyssä", vaikka namespacea ei nimetä. Yksittäisen sovelluksen deployaukseen, konfigurointiin, image-buildeihin tai troubleshoottaukseen käytä csc-rahti-skilliä — tämä skilli on read-only tilannekuva koko namespacesta, ei korjaustyökalu.
argument-hint: "[namespace tai sovelluksen nimi, oletus: kaikki]"
compatibility: Vaatii oc CLI:n ja voimassa olevan Rahti-kirjautumisen (oc login tai csc-rahti-skillin Connect-Rahti.ps1). Ehdottomasti read-only — ei kirjoittavia oc-komentoja.
---

# Rahti Deploy Audit

Koko tuotannon tilannekuva CSC Rahti 2:sta yhdellä ajolla: onko jokainen sovellus pystyssä, vastaavatko routet, ja näkyykö hälyttäviä eventtejä.

**Tämä skilli ei korjaa mitään.** Korjaukset: [[csc-rahti]].

## Työnkulku

### 1. Autentikointi

```powershell
oc whoami
```

Jos komento epäonnistuu, kirjautuminen puuttuu tai on vanhentunut. Jos service account
on käytössä, aja skripti — **älä ohjaa käyttäjää turhaan web-konsoliin**:

```powershell
& "$HOME\.claude\skills\csc-rahti\scripts\Connect-Rahti.ps1" -Namespace <namespace>
```

Muuten henkilökohtainen `oc login` konsolin *Copy login command* -valikosta.
Yksityiskohdat ja tokenin elinkaari: [[csc-rahti]] → Authentication. **Älä koskaan tulosta tokenia.**

### 2. Namespacet

```powershell
oc projects -q
```

Oletuksena auditoi kaikki näkyvät namespacet. Jos käyttäjä nimesi yhden namespacen tai sovelluksen, rajaa siihen.

### 3. Keruu

Ensisijaisesti kerääjäskriptillä — yksi ajo kymmenen `oc`-kutsun sijaan:

```powershell
& "$HOME\.claude\skills\rahti-audit\scripts\Get-RahtiStatus.ps1" | ConvertFrom-Json
```

Skripti on read-only ja hoitaa myös route-tarkistukset uusintayrityksineen. Parametrit: `-Namespace <ns1>,<ns2>`, `-SkipRoutes`, `-TimeoutSec 15`.

**Jos skripti epäonnistuu, älä jää jumiin siihen** — kerää samat tiedot raa'asti. Aja kutsut **rinnakkain samassa viestissä**, yksi tool-call per namespace per resurssityyppi:

```powershell
oc get deployments,statefulsets -n <ns> -o wide
oc get pods -n <ns>
oc get routes -n <ns>
oc get events -n <ns> --field-selector type=Warning --sort-by=.lastTimestamp
oc get resourcequota -n <ns>
```

### 4. Route-terveys

Jokaiselle routelle HTTP-status ja vasteaika. **Kaksi yritystä ennen kuin merkitset routen alas** — cold start tai skaalattu-nollaan-tilanne antaa ensimmäisellä pyynnöllä timeoutin vaikka sovellus on terve. Kerääjäskripti tekee tämän automaattisesti.

### 5. Syvennä vain poikkeamiin

Älä lue logeja terveistä podeista. Vain näissä:

| Havainto | Seuraava komento |
|---|---|
| `CrashLoopBackOff` | `oc logs deployment/<name> -n <ns> --previous` |
| `ImagePullBackOff` / `ErrImagePull` | `oc describe pod <pod> -n <ns>` → katso pull secret ja tagi |
| `Pending` | `oc describe pod <pod> -n <ns>` → useimmiten kiintiö täynnä |
| `OOMKilled` (exit 137) | `oc adm top pods -n <ns>` + muistilimiitti |
| Korkea restart-luku | `oc logs ... --previous` **ja** podin `age` — ks. gotchas |
| `Failed`-tilainen `*-build`-podi | `oc logs <build-podi> -n <ns>` → build kaatui, uusi image jäi syntymättä |

### 6. Raportoi

## Raportin muoto

```
## Yhteenveto: [🟢 ei kriittistä / 🟡 huomioitavaa / 🔴 tuotanto rikki]

## Namespace <ns>
[taulukko: sovellus | ready | restartit | route | HTTP | huomio]

## Namespace <ns2>
[sama taulukko]

## Hälytykset
[vain poikkeamat: mikä, mistä näkyy, 1 lause tulkintaa]

## Kiintiöt
[vain jos jokin resurssi > 80 % — muuten jätä osio kokonaan pois]

## Suositus
[priorisoitu lista, tai "ei toimenpiteitä"]
```

Älä listaa jokaista podia ja eventtiä. Käyttäjä haluaa signaalin, ei `oc get` -dumppia. Terve namespace mahtuu yhteen taulukkoon.

## Gotchas

Nämä erottavat todellisen hälytyksen kohinasta. Useimmat "punaiselta" näyttävät rivit ovat vaarattomia:

- **Restart-luku ei yksin ole hälytys.** Kuukausia ajanut podi kerää restartteja normaalista OOM-kierrätyksestä ja nodejen huollosta. Suhteuta aina `age`en: 40 restarttia 90 päivässä on eri asia kuin 40 restarttia tunnissa. Katso `--previous`-logi ennen kuin merkitset punaiseksi.
- **504 routella = HAProxyn 30 s oletustimeout**, ei sovellus alhaalla. Pitkille pyynnöille annotaatio `haproxy.router.openshift.io/timeout`. Yksityiskohdat: [[csc-rahti]] → "504 Gateway Time-out on long requests?".
- **Cold start antaa väärän hälytyksen.** Ensimmäinen pyyntö vähän käytettyyn sovellukseen voi aikakatkaista vaikka kaikki on kunnossa. Siksi kaksi yritystä.
- **401/403 route ei ole vika.** Moni sovellus vaatii autentikoinnin — HTTP 401 tarkoittaa että sovellus **vastaa**, eli se on pystyssä. Merkitse 🟢 ja huomio "vaatii kirjautumisen". Vain 5xx, yhteysvirhe ja timeout ovat hälytyksiä.
- **Päättyneet podit eivät ole vikoja.** `oc get pods` näyttää ne sarakkeessa `Completed`/`Error`, mutta JSONin `status.phase` on `Succeeded`/`Failed` — kerääjäskripti palauttaa jälkimmäiset. Älä laske `Succeeded`-podeja alas olevaksi sovellukseksi; ne ovat päättyneitä Job-, CronJob- ja build-ajoja.
- **Build-podit (`<sovellus>-<n>-build`) kasautuvat namespaceen** BuildConfigin jokaisesta ajosta. `Succeeded` on normaali. **`Failed` on aito löydös:** build kaatui, eli uusi image ei koskaan valmistunut ja deployment ajaa yhä vanhaa koodia — vaikka podi näyttää `Ready 1/1` ja route palauttaa 200. Tämä on juuri se vika jota pelkkä terveystarkistus ei löydä. Katso `oc logs <build-podi> -n <ns>` ja [[csc-rahti]] → "Monitoring builds".
- **Tyhjä `resourcequota` ei ole virhe.** Rahtissa kiintiö on CSC-laskentaprojektin tasolla eikä näy aina namespacen `ResourceQuota`-objektina — `oc get resourcequota -n <ns>` palauttaa tällöin "No resources found". Kokonaiskiintiö näkyy komennolla `oc describe AppliedClusterResourceQuotas`. Normaali tila, ei keruuvirhe.
- **Kiintiö täynnä → podit jäävät `Pending`iin ilman selkeää virheilmoitusta.** Kiintiö on jaettu koko CSC-laskentaprojektin kesken, ei per namespace. Tarkista `oc describe quota -n <ns>` ja `oc describe pod` aina kun näet Pendingiä.
- **`oc projects` näyttää vain ne namespacet joihin tunnuksella on oikeus.** Service accountille lista on tyypillisesti suppeampi kuin henkilötunnukselle. Puuttuva namespace ei siis tarkoita ettei sitä olisi olemassa — se tarkoittaa ettei tällä tunnuksella ole sinne oikeuksia.
- **Vanha image ajossa ei näy podin tilassa.** Jos deployment on `Ready 1/1` mutta koodimuutos ei näy, kyse on todennäköisesti pysähtyneestä image-triggeristä — ei terveysongelmasta. Ks. [[csc-rahti]] → "Deployment not updating after push?".

## Milloin lopettaa

**Read-only ehdottomasti.** Älä aja `oc delete`, `oc scale`, `oc rollout restart`, `oc set image`, `oc annotate` tai `oc apply` — et edes silloin kun korjaus näyttää itsestään selvältä. Nämä kuuluvat [[csc-rahti]]-skillille, jolla on niitä varten omat turvasääntönsä.

Raportoi löydökset ja ehdota priorisoitu korjauslista. Jos käyttäjä pyytää korjaamaan, vaihda skilliä — älä laajenna tämän skillin oikeuksia lennossa.
