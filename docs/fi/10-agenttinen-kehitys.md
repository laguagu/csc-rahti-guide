# 10. Agenttinen kehitys: skillit Rahti-työhön

> Tämä repositorio sisältää neljä **agenttiskilliä**, jotka opettavat tekoälyagentin
> (Claude Code, Codex, Cursor tms.) käyttämään CSC:n ympäristöjä oikein. Skilli on
> pelkkä markdown-tiedosto — ei asennettavaa ohjelmistoa, ei API-avainta.

## Sisällys

- [Mikä skilli on](#mikä-skilli-on)
- [Repositorion skillit](#repositorion-skillit)
- [Asennus](#asennus)
- [Käyttö](#käyttö)
- [UI vai CLI vai agentti](#ui-vai-cli-vai-agentti)
- [Mitä agentti ei voi tehdä](#mitä-agentti-ei-voi-tehdä)
- [Turvasäännöt](#turvasäännöt)
- [Skillien muokkaus](#skillien-muokkaus)
- [Skillit useammalla koneella](#skillit-useammalla-koneella)
- [Lue lisää](#lue-lisää)

## Mikä skilli on

Skilli on kansio, jossa on `SKILL.md` ja mahdollisia lisätiedostoja:

```
csc-rahti/
├── SKILL.md              # ohjeet agentille + kuvaus milloin skilli otetaan käyttöön
├── references/           # syventävät dokumentit, luetaan vain tarvittaessa
│   ├── routes.md
│   ├── authentication.md
│   └── …
├── scripts/              # ajettavat apuskriptit
└── tests/                # skriptien testit
```

`SKILL.md`:n alussa on YAML-lohko, jonka `description`-kenttä kertoo agentille **milloin**
skilli kannattaa ottaa käyttöön. Agentti lukee kuvaukset jatkuvasti, mutta koko sisällön
vasta kun se on relevantti — näin kymmenetkään skillit eivät täytä konteksti-ikkunaa.

Käytännön hyöty: ilman skilliä agentti arvaa Rahdin yksityiskohdat väärin (vanhentunut
konsolin navigaatio, `runAsUser` manifestissa, unohtunut ImageStream). Skillin kanssa se
tietää talon tavat.

## Repositorion skillit

| Skilli | Mihin | Milloin laukeaa |
| --- | --- | --- |
| **[csc-rahti](../../.claude/skills/csc-rahti/)** | Rahti-deployaus, imaget, routet, salaisuudet, Satama, Allas, Aitta-LLM-API | "deployaa Rahtiin", "oc", "rahtiapp.fi", "imagestream", "satama" |
| **[rahti-audit](../../.claude/skills/rahti-audit/)** | Read-only tilannekuva koko namespacesta | "onko tuotanto kunnossa", "auditoi Rahti", "crashloop" |
| **[csc-roihu](../../.claude/skills/csc-roihu/)** | Roihu-supertietokone: Slurm, GH200-GPU:t, moduulit | "sbatch", "aja GPU:lla", "supertietokone" |
| **[csc-lumi](../../.claude/skills/csc-lumi/)** | LUMI: AMD MI250X, ROCm, LUMI-ohjelmistopino | "LUMI", "ROCm", "MI250X" |

Työnjako on tarkoituksellinen: `rahti-audit` on **read-only** eikä saa korjata mitään,
`csc-rahti` tekee muutokset. Näin "katso mikä on rikki" ei koskaan vahingossa muuta
tuotantoa.

Valinta CSC-palveluiden välillä lyhyesti:

| Tarve | Palvelu | Skilli |
| --- | --- | --- |
| Web-sovellus tai API pystyyn | Rahti | csc-rahti |
| Mallin koulutus tai iso eräajo NVIDIA-GPU:lla | Roihu | csc-roihu |
| Sama AMD-GPU:lla, EuroHPC-kiintiöllä | LUMI | csc-lumi |
| Valmis LLM-päätepiste ilman omaa GPU:ta | Aitta | csc-rahti (Aitta-osio) |

## Asennus

### Vaihtoehto 1: kloonaa repositorio (helpoin)

Kun avaat tämän repositorion Claude Codella, skillit ovat heti käytössä — ne ovat
kansiossa `.claude/skills/`, jonka Claude Code lukee projektikohtaisesti.

```bash
git clone <tämän-repon-url>
cd csc-rahti-guide
claude
```

### Vaihtoehto 2: kopioi omaan käyttöön (kaikkiin projekteihin)

Kopioi haluamasi skillit henkilökohtaiseen skillikansioosi, niin ne ovat käytössä
kaikissa projekteissa:

```bash
# macOS / Linux
cp -r .claude/skills/csc-rahti ~/.claude/skills/
cp -r .claude/skills/rahti-audit ~/.claude/skills/
```

```powershell
# Windows PowerShell
Copy-Item -Recurse .claude\skills\csc-rahti  "$HOME\.claude\skills\"
Copy-Item -Recurse .claude\skills\rahti-audit "$HOME\.claude\skills\"
```

Tarkista tulos Claude Codessa komennolla `/skills`.

### Vaihtoehto 3: jaettu `.agents/skills` -kansio

Osa agenttityökaluista lukee skillit polusta `.agents/skills/`
([agentskills.io](https://agentskills.io)-konventio). Sama `SKILL.md` kelpaa molemmille,
joten tiedostoja ei kannata monistaa — tee linkki:

```bash
# macOS / Linux
mkdir -p ~/.agents/skills
ln -s ~/.claude/skills/csc-rahti ~/.agents/skills/csc-rahti
```

```powershell
# Windows: hakemistojunktio (ei vaadi järjestelmänvalvojan oikeuksia)
New-Item -ItemType Junction -Path "$HOME\.agents\skills\csc-rahti" `
         -Target "$HOME\.claude\skills\csc-rahti"
```

> **Claude Code ei lue `.agents/skills`-polkua** — sille riittää `~/.claude/skills/` tai
> projektin `.claude/skills/`. Linkki on siis muita työkaluja varten, ja tehdään siihen
> suuntaan että Claude Coden polku on alkuperäinen ja `.agents` osoittaa siihen.
>
> Jos työkalusi lukee ohjeensa `AGENTS.md`-tiedostosta, lisää sinne rivi, joka viittaa
> tämän repositorion `docs/`-kansioon ja skilleihin.

### Riippuvuudet

Skillit itsessään eivät vaadi mitään, mutta niiden neuvomat komennot vaativat:

| Työkalu | Mihin | Tarkistus |
| --- | --- | --- |
| `oc` | kaikki Rahti-toiminta | `oc version --client` |
| `docker` tai `podman` | imagejen rakennus | `docker --version` |
| PowerShell 7 | `csc-rahti`- ja `rahti-audit`-skriptit | `pwsh --version` |
| `openstack` | Allas-tunnukset | `openstack --version` |

## Käyttö

**Kutsu nimellä** (Claude Code, slash-komento):

```
/csc-rahti Miten saan omalle sovellukselle osoitteen demo.2.rahtiapp.fi?
```

**Tai kuvaile tehtävä** — skilli laukeaa kuvauksensa perusteella itsestään:

```
Deployaa tämä Next.js-sovellus Rahtiin projektiin minun-projekti,
portti 3000, ja tee sille route.
```

```
Tarkista onko Rahdissa mitään rikki.
```

```
gaik-demo palauttaa 504 kun kysely kestää yli puoli minuuttia. Korjaa.
```

Tyypillinen agenttityönkulku Rahtiin:

1. **Kirjaudu itse** — agentti ei läpäise MFA:ta (ks. alla). Aja `oc login` tai
   `Connect-Rahti.ps1`.
2. **Anna tehtävä.** Agentti lukee skillin, tarkistaa tilanteen `oc get`-komennoilla ja
   ehdottaa muutokset.
3. **Tarkista ehdotus** ennen kuin hyväksyt kirjoittavat komennot.
4. **Anna sen ajaa deploy** ja lukea `oc rollout status` -tuloste.

## UI vai CLI vai agentti

| Tehtävä | Suositus | Miksi |
| --- | --- | --- |
| Ensimmäinen tutustuminen | **UI** | Näet mitä objekteja syntyy |
| Kertaluontoinen demo pystyyn | **UI** | Nopein, ei tiedostoja |
| Toistuva deployaus | **CLI + manifestit** | Versionhallinnassa, toistettavissa |
| Ympäristömuuttujan pikamuutos | **UI** tai `oc set env` | Molemmat käynnistävät rullauksen |
| Salaisuuksien luonti | **CLI** | `--from-literal` on tarkka; lomake ei näytä lopputulosta |
| Lokien lukeminen | **UI** kevyeen, `oc logs -f` vakavaan | UI katkaisee pitkät lokit |
| Tuotannon tilannekuva | **Agentti** (`rahti-audit`) | Kymmenen komentoa yhdellä ajolla, raportoi vain poikkeamat |
| Vianmääritys | **Agentti + CLI** | Agentti osaa etenemisjärjestyksen, sinä päätät korjauksen |
| Kiintiöiden nosto, oikeudet | **UI + palvelupiste** | Vaatii ihmisen |

Nyrkkisääntö: **UI oppimiseen ja kertaluontoiseen, CLI toistettavaan, agentti
rutiinien nopeuttamiseen.** Agentti ei korvaa sitä, että ymmärrät mitä se tekee — siksi
luvut 1–9 kannattaa lukea vaikka antaisit agentin tehdä työn.

## Mitä agentti ei voi tehdä

- **Läpäistä CSC:n MFA:ta.** Henkilökohtainen kirjautuminen on aina ihmisen tehtävä.
  Agentti voi käyttää valmiiksi luotua service accountia, mutta ei luoda ensimmäistä
  tunnusta ilman että olet kirjautunut.
- **Hakea tokenia web-konsolista.** *Copy login command* vaatii selainistunnon.
- **Nostaa kiintiötä tai avata Rahti-oikeuksia** — ne kulkevat MyCSC:n ja palvelupisteen
  kautta.
- **Tietää projektikohtaisia rajoja arvaamatta.** Anna sen ajaa
  `oc describe limitranges` sen sijaan että luottaisit oletusarvoihin.

## Turvasäännöt

Skillit on kirjoitettu näiden sääntöjen mukaan, ja samat pätevät sinuun:

1. **Tokeneita ei tulosteta.** Ei chattiin, ei lokiin, ei committiin. Skriptit välittävät
   tokenin suoraan `oc`:lle.
2. **Salaisuudet repositorion ulkopuolelle.** Service account -tokenit tallennetaan
   erilliseen env-hakemistoon, ei skilliin eikä projektiin.
3. **Read-only pysyy read-only.** `rahti-audit` ei aja `oc delete`, `oc scale`,
   `oc apply` -komentoja edes silloin kun korjaus näyttää itsestään selvältä.
4. **Kirjoittavat komennot tuotantoon vahvistetaan.** `oc delete`, `oc scale --replicas=0`
   ja `oc apply` ovat asioita, jotka kannattaa lukea ennen hyväksymistä.
5. **Vähimmät oikeudet.** `view` auditointiin, `edit` deployaukseen, `admin` vain jos
   oikeuksien hallinta on oikeasti tarpeen.

## Skillien muokkaus

Skillit ovat tarkoituksella luettavaa markdownia — muokkaa niitä omaan ympäristöösi:

- Vaihda `<namespace>`-paikanpitäjät oman projektisi nimeen, jos työskentelet vain yhdessä.
- Lisää `references/`-kansioon oman organisaatiosi käytännöt.
- Pidä `description`-kenttä kuvaavana: se ratkaisee, laukeaako skilli oikeaan aikaan.
- Skriptit ovat testattuja — jos muutat niitä, aja testit:

```powershell
pwsh -NoProfile -Command "& '.claude/skills/csc-rahti/tests/RahtiCredentials.Tests.ps1'"
```

**Älä** committaa skilliin projektikohtaisia namespaceja, tunnuksia, asiakkaiden nimiä
tai tokeneita, jos repositorio on julkinen.

## Skillit useammalla koneella

Jos käytät useampaa konetta, älä kopioi skillejä koneelta toiselle — ne eriytyvät
viikossa. Pidä yksi kansio ainoana lähteenä ja linkitä siihen:

```powershell
# Kansio joka synkronoituu koneiden välillä (OneDrive, Dropbox, git-repo…)
$src = "$HOME\OneDrivegents-setup\skills"

# Claude Code lukee tämän polun
New-Item -ItemType Junction -Path "$HOME\.claude\skills" -Target $src
```

```bash
# macOS / Linux
ln -s ~/Sync/agents-setup/skills ~/.claude/skills
```

Sama kansio voi palvella useaa työkalua yhtä aikaa: yksi lähde, monta linkkiä.
Salaisuudet eivät kuulu tähän kansioon — pidä ne erillään (esim. `agents-setup/env/`),
jotta skillien jakaminen ei koskaan jaa tokeneita.

Git-repo synkronointikansiona on paras vaihtoehto tiimille: muutokset ovat
katselmoitavissa ja historia näkyy.

## Lue lisää

**Skillit yleisesti**

- [What are Skills?](https://support.claude.com/en/articles/12512176-what-are-skills) — Anthropicin yleiskuvaus
- [Claude Code: Skills](https://code.claude.com/docs/en/skills) — `SKILL.md`-formaatti, frontmatter-kentät ja hakupolut
- [agentskills.io](https://agentskills.io) — työkaluriippumaton spesifikaatio, jota tämän repon skillit noudattavat

**Skillien paketointi laajempaan jakeluun**

Jos skillejä alkaa kertyä ja niitä halutaan jakaa organisaatiossa, seuraava askel on
paketoida ne pluginiksi — skillit, työkalut ja konfiguraatio yhtenä asennettavana
kokonaisuutena:

- [Agent plugins: package your skills, tools and more](https://developers.googleblog.com/agent-plugins-package-your-skills-tools-and-more/) — mitä plugin sisältää ja milloin se kannattaa
- [Claude Code: Plugins](https://code.claude.com/docs/en/plugins) — plugin-rakenne ja asennus

> Spesifikaatiosivu `agent-plugins.org` ei tätä kirjoitettaessa vastaa oikealla
> TLS-sertifikaatilla (selain varoittaa), joten yllä on toimivat lähteet.

Tämän repon neljä skilliä toimivat sellaisenaan ilman paketointia, joten pluginia ei
tarvita ennen kuin jakelu kasvaa yksittäisiä käyttäjiä suuremmaksi.

**CSC:n omat dokumentit**

- [Rahti](https://docs.csc.fi/cloud/rahti/) · [Satama](https://docs.csc.fi/cloud/satama/) · [Allas](https://docs.csc.fi/data/Allas/)
- [Roihu](https://docs.csc.fi/computing/systems-roihu/) · [LUMI](https://docs.lumi-supercomputer.eu/) · [Aitta](https://aitta.csc.fi/)

---

**Edellinen:** [9. Vianmääritys](09-vianmaaritys.md) · **Takaisin:** [Etusivu](../../README.md)
