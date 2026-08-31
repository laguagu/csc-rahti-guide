# 1. Aloitus: pääsy, kirjautuminen ja projektit

> Mitä Rahti on, miten sinne saa pääsyn, miten kirjaudut selaimella ja komentoriviltä,
> ja mitä resursseja projektisi saa käyttää.

## Sisällys

- [Mikä Rahti 2 on](#mikä-rahti-2-on)
- [Edellytykset](#edellytykset)
- [Kirjautuminen selaimella](#kirjautuminen-selaimella)
- [Projektin luonti](#projektin-luonti)
- [`oc`-komentorivityökalu](#oc-komentorivityökalu)
- [Kirjautuminen komentoriviltä](#kirjautuminen-komentoriviltä)
- [Service account pitkäkestoiseen käyttöön](#service-account-pitkäkestoiseen-käyttöön)
- [Kiintiöt ja resurssirajat](#kiintiöt-ja-resurssirajat)
- [Tietoturvarajoitukset](#tietoturvarajoitukset)

## Mikä Rahti 2 on

Rahti 2 on CSC:n konttipilvi. Se pyörii **OKD:llä**, joka on Red Hat OpenShiftin avoin
yhteisöversio. Käytännössä: kirjoitat Dockerfilen, työnnät imagen rekisteriin ja Rahti
ajaa sen podina, antaa sille julkisen HTTPS-osoitteen ja käynnistää sen uudelleen jos se
kaatuu.

| Rahti sopii | Rahti ei sovi |
| --- | --- |
| Web-sovellukset ja API:t | GPU-laskenta ja mallien koulutus → [Roihu](https://docs.csc.fi/computing/roihu/) tai [LUMI](https://docs.csc.fi/computing/lumi/) |
| Jatkuvasti päällä olevat palvelut | Eräajot ja Slurm-jobit → Roihu |
| Mikropalvelut ja taustapalvelut | Virtuaalikoneiden hallinta → [cPouta](https://docs.csc.fi/cloud/pouta/) |
| Demot ja opetuskäyttö | Root-oikeuksia vaativat kontit (ei mahdollista, ks. alla) |

**Keskeiset osoitteet:**

| Mitä | Osoite |
| --- | --- |
| Web-konsoli | `https://console.rahti.csc.fi` |
| API-palvelin | `https://api.2.rahti.csc.fi:6443` |
| Sisäinen konttirekisteri | `image-registry.apps.2.rahti.csc.fi` |
| Sovellusten URL-avaruus | `*.2.rahtiapp.fi` |
| Ulosmenevä IP (palomuurisääntöihin) | `86.50.229.150` — voi muuttua, tarkista aina [dokumentaatiosta](https://docs.csc.fi/cloud/rahti/configurations/egress-ip/) |

## Edellytykset

1. **CSC-käyttäjätunnus** — luodaan [MyCSC](https://my.csc.fi/)-palvelussa.
2. **Laskentaprojekti, jolle Rahti on otettu käyttöön:**
   - Kirjaudu [my.csc.fi](https://my.csc.fi) → *My Projects*
   - Valitse projekti → avaa palvelulistasta **Rahti** → hyväksy käyttöehdot → *Apply for access*
   - CSC vahvistaa hakemuksen. Oikeuksien synkronointiin voi mennä ~10 minuuttia.
3. **Docker tai Podman** paikallisesti, jos rakennat imaget itse.
4. **`oc`-komentorivityökalu**, jos et halua tehdä kaikkea selaimessa.

> Sama laskentaprojekti voi olla käytössä myös cPoutassa tai Roihussa — Rahti lisätään
> vain palveluvalikoimaan.

## Kirjautuminen selaimella

Mene osoitteeseen <https://console.rahti.csc.fi> ja paina **LOGIN**.

![Rahti-konsolin kirjautumissivu](../images/rahti-login.jpg)

Valitse tunnistautumistapa: **Haka** (korkeakoulut), **Virtu** (valtionhallinto) tai
**CSC**. Kaikki vaativat monivaiheisen tunnistautumisen (MFA) — pakollinen 25.11.2025
alkaen. MFA:ta ei voi ohittaa skriptillä eikä tekoälyagentilla.

> **"User not found" kirjautumisen jälkeen?** Tunnus on olemassa, mutta laskentaprojektille
> ei ole vielä myönnetty Rahti-oikeutta, tai synkronointi on kesken. Tarkista MyCSC:stä.

## Projektin luonti

Rahdissa kaikki ajetaan **projektin** (Kubernetes-termein *namespace*) sisällä. Projektilla
on oma verkko, omat salaisuudet ja oma käyttöoikeuslista.

**Selaimessa:** vasemmasta valikosta *Home → Projects* → **Create Project**.

**Komentoriviltä** — huomaa `csc_project`-kuvaus, joka kytkee Rahti-projektin
laskentaprojektiin ja siten laskutukseen:

```bash
oc new-project minun-projekti --description="csc_project: 2001234"
```

Oletuksena kaikki laskentaprojektin jäsenet saavat admin-oikeudet luotuun
Rahti-projektiin. Yksittäisiä käyttäjiä voi lisätä konsolissa
*User Management → RoleBindings*.

> **Nimeäminen:** projektin nimi näkyy sovelluksen oletusosoitteessa muodossa
> `<sovellus>-<projekti>.2.rahtiapp.fi`, joten valitse lyhyt ja selkeä nimi.

## `oc`-komentorivityökalu

`oc` on OpenShiftin CLI. Se osaa kaiken minkä `kubectl`, ja lisäksi OKD-spesifit asiat
(routet, imagestreamit, buildconfigit).

Lataa binääri suoraan konsolista: **?-valikko → Command Line Tools**.

![Command Line Tools -sivu](../images/rahti-cli-tools.jpg)

Windowsilla helpoin tapa on paketinhallinta:

```powershell
# Scoop
scoop install openshift-cli

# tai lataa zip yllä olevalta sivulta ja pura oc.exe PATHissa olevaan kansioon
```

Tarkista asennus:

```bash
oc version --client
```

## Kirjautuminen komentoriviltä

1. Klikkaa konsolissa oikeasta yläkulmasta nimeäsi → **Copy login command**

   ![Copy login command -valikko](../images/rahti-copy-login-command.jpg)

2. Paina avautuvalla sivulla **Display Token**
3. Kopioi komento ja aja se terminaalissa:

```bash
oc login https://api.2.rahti.csc.fi:6443 --token=sha256~<sinun-tokenisi>
```

Kirjautuminen on konekohtainen ja jaettu kaikkien terminaali-ikkunoiden kesken.
**Henkilökohtainen token vanhenee noin vuorokaudessa.**

Tarkista kuka olet ja missä projektissa:

```bash
oc whoami                 # käyttäjätunnus tai system:serviceaccount:<ns>:<nimi>
oc project                # nykyinen projekti
oc projects               # kaikki projektit joihin on pääsy
oc project minun-projekti # vaihda projektia
```

## Service account pitkäkestoiseen käyttöön

Henkilökohtainen token vanhenee joka päivä, mikä on kiusallista CI-putkissa,
deploy-skripteissä ja tekoälyagenteilla. Ratkaisu on **service account**: sillä ei ole
MFA:ta ja sen tokenin eliniän saa itse valita.

```bash
# 1. Luo tunnus projektiin
oc create serviceaccount deployer-bot -n minun-projekti

# 2. Anna sille oikeudet (view = luku, edit = deployaus, admin = myös oikeuksien hallinta)
oc adm policy add-role-to-user edit \
  system:serviceaccount:minun-projekti:deployer-bot -n minun-projekti

# 3. Pyydä token — tässä vuosi
oc create token deployer-bot -n minun-projekti --duration=8760h
```

Säilytä token salaisuuksien hallinnassa tai gitignoratussa env-tiedostossa — **älä
koskaan committaa sitä**. Käyttö:

```bash
oc login https://api.2.rahti.csc.fi:6443 --token=<service-account-token>
```

Peruutus on yhtä nopeaa:

```bash
oc adm policy remove-role-from-user edit \
  system:serviceaccount:minun-projekti:deployer-bot -n minun-projekti
oc delete serviceaccount deployer-bot -n minun-projekti
```

> Käytä eri tunnusta eri tarkoituksiin. Pelkkään imagen työntämiseen riittää rooli
> `system:image-pusher`, ei `edit`.
>
> Tämän repositorion [csc-rahti-skilli](../../.claude/skills/csc-rahti/) sisältää
> PowerShell-skriptit (`Initialize-RahtiCredential.ps1`, `Connect-Rahti.ps1`), jotka
> automatisoivat koko elinkaaren ja tallettavat tokenin repositorion ulkopuolelle.

## Kiintiöt ja resurssirajat

Kiintiö on **laskentaprojektikohtainen ja jaettu kaikkien sen Rahti-projektien kesken** —
ei siis per sovellus. Oletuskiintiö uudelle laskentaprojektille:

| Resurssi | Oletus |
| --- | --- |
| Virtuaaliytimet | 4 |
| Muisti | 16 GiB |
| Levy (PVC) | 100 GiB |
| Väliaikaislevy (ephemeral) | 5 GiB |
| ImageStreamien määrä | 20 |
| Podien yhtäaikainen määrä | 100 |
| PVC:iden määrä | 20 |

```bash
oc describe AppliedClusterResourceQuotas   # koko laskentaprojektin käyttö
oc describe limitranges -n <namespace>     # yksittäisen kontin rajat
```

**LimitRange** määrää, mitä yksittäinen kontti saa pyytää — ja mitä se saa jos et pyydä
mitään:

![LimitRange-näkymä konsolissa](../images/rahti-limitrange.jpg)

| Tyyppi | CPU | Muisti |
| --- | --- | --- |
| `requests` (varaus) | 100m | 500Mi |
| `limits` (katto) | 500m | 1Gi |

Lisäksi: `limits`/`requests`-suhde saa olla korkeintaan 5, yksittäinen image enintään
5 GiB ja yksittäinen PVC enintään 100 GiB. Yllä olevassa kuvassa projektille on myönnetty
oletusta suuremmat rajat — **tarkista aina oman projektisi todelliset arvot**, älä oleta.

Lisäkiintiötä haetaan [CSC:n palvelupisteestä](mailto:servicedesk@csc.fi) tapauskohtaisesti.

## Tietoturvarajoitukset

Rahti on monen asiakkaan jaettu ympäristö, joten kontteja rajoitetaan:

- **Root ei ole sallittu.** Kontti, joka vaatii `USER root`, ei käynnisty.
- **Satunnainen UID.** Kontti saa käynnistyessään projektikohtaisen UID:n (esim.
  `1000620000`). Älä siis kirjoita `runAsUser`-arvoa manifestiin äläkä oleta UID:tä
  `1001`. Ryhmä on aina `0`.
- **Restricted-v2 -käytäntö:** `allowPrivilegeEscalation` ei saa olla `true`, kaikki
  capabilityt on pudotettava (`capabilities.drop: ALL`, poikkeuksena `NET_BIND_SERVICE`),
  ja `seccompProfile` joko tyhjä tai `RuntimeDefault`.
- **Privileged-tila on estetty.**

Käytännön seuraus Dockerfileen: tee kirjoitettavista hakemistoista ryhmän 0
kirjoitettavia. Katso [09 Vianmääritys](09-vianmaaritys.md#permission-denied-tiedostoa-kirjoitettaessa)
ja skillin [Dockerfile-esimerkit](../../.claude/skills/csc-rahti/references/dockerfile-examples.md).

---

**Seuraava:** [2. Sovelluksen julkaisu →](02-julkaisu.md)
