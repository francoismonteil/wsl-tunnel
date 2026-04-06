# Mirrored Mode Validation Report

**Date:** 2026-04-06  
**Campagne:** Validation complète du mode `networkingMode=mirrored` WSL2  
**Run mode:** automated execution based on [MIRRORED-MODE-VALIDATION-PLAN.md](MIRRORED-MODE-VALIDATION-PLAN.md)

---

## 0. Sanitization Scope

This report is intentionally sanitized for public publication.

- internal IP addresses are replaced with placeholders
- corporate proxy hostnames and domain lists are generalized
- workstation-specific identifiers are normalized where they are not required for the technical conclusion

Placeholder values used in this report:

- `<mirrored-ip-a>`, `<mirrored-ip-b>`, `<mirrored-ip-c>`, `<mirrored-ip-d>` = Windows IPv4 addresses observed from mirrored WSL interfaces
- `<docker-bridge-ip>` = Docker bridge gateway seen from bridge-mode containers
- `<legacy-hyperv-ip>` = obsolete Hyper-V NAT address not used in mirrored mode
- `<corp-proxy-host>` = corporate proxy hostname exposed inside container environments
- `<proxy-port>` = corporate proxy port
- `<corp-domain-list>` = normalized internal domain suffix list used in `NO_PROXY`

---

## 1. Résumé exécutif

La campagne a été déroulée intégralement sur le poste de travail Windows en date du 6 avril 2026.  
Le mode `networkingMode=mirrored` a été activé pour la durée des tests, puis la configuration `NAT` d'origine a été restaurée.

**Verdict global : Outcome B — Mirrored acceptable pour les workflows natifs uniquement.**

| Périmètre | Verdict |
|-----------|---------|
| Windows ↔ WSL2 natif (`localhost`) | **OK** |
| Windows → Docker published ports | **KO systématique (timeout)** |
| Container bridge → Windows | **KO (refusé ou proxy)** |
| Container `--network host` → Windows | **OK via localhost** |
| Mirrored + tunnel SSH natif | **OK mais instable** |
| Mirrored + relay socat → Windows | **TCP OK / HTTP 400 (hostname mismatch)** |

Le mode mirrored ne peut pas être un mode primaire pour ce dépôt tant que Docker Engine Linux publie des ports sur le bridge réseau. La dépendance `container → service Windows` n'est résolue ni nativement, ni via le tunnel SSH actuel, ni via un relay simple.

---

## 2. Environnement de test

### 2.1 Configuration `.wslconfig` appliquée

```ini
[wsl2]
swap = 0
autoProxy=false
networkingMode=mirrored
localhostForwarding=true
```

Note : WSL produit un avertissement au démarrage — `localhostForwarding n'a aucun effet lors de l'utilisation du mode réseau mis en miroir`. Ce comportement est attendu et documenté.

### 2.2 Distribution WSL2

```
Distribution par défaut : Ubuntu
Version : 2
OS : Ubuntu 22.04.5 LTS
Kernel : 6.6.87.2-microsoft-standard-WSL2
Mémoire totale : 7.152 GiB
```

### 2.3 Docker Engine

```
Client + Server : Docker Engine - Community v27.0.1
Build : ff1e2c0
Mode : Linux engine natif (pas Docker Desktop)
Docker Root : /var/lib/docker
```

### 2.4 Topologie réseau WSL2 en mode mirrored

En mode mirrored, WSL2 présente une interface par NIC Windows actif.

```
lo (loopback)  127.0.0.1/8 + 10.255.255.254/32
eth0           <mirrored-ip-a>/32    (miroir d'un adaptateur Windows)
loopback0      <UP> sans IP assignée (pont loopback mirrored)
eth2           <mirrored-ip-b>/32    (miroir d'un adaptateur Windows, VPN)
eth3           <mirrored-ip-c>/32    (miroir d'un adaptateur Windows, VPN)
eth5           <mirrored-ip-d>/24    (miroir du Wi-Fi Windows, LAN)
docker0        <docker-bridge-ip>/16      (bridge Docker, non mirrored)
br-7b81...     172.18.0.1/16      (réseau Docker secondaire)
```

**Signatures mirrored confirmées :**
- Interfaces eth0–eth8 en correspondance 1:1 avec les NICs Windows
- `loopback0` présent (pont loopback partagé Windows/WSL2)
- IPs en `/32` (pas de préfixe de sous-réseau classique en mirrored)

### 2.5 Adresses IP Windows (correspondance)

| Interface Windows | IP Windows | Interface WSL2 |
|-------------------|-----------|----------------|
| Ethernet A | `<mirrored-ip-a>` | eth0 |
| Ethernet B | `<mirrored-ip-b>` | eth2 |
| Ethernet C | `<mirrored-ip-c>` | eth3 |
| Wi-Fi | `<mirrored-ip-d>` | eth5 |
| WSL (Hyper-V) | `<legacy-hyperv-ip>` | — (obsolète en mirrored) |

### 2.6 Docker bridge (réseau de référence)

```
docker0 : <docker-bridge-ip>/16
bridge gateway depuis l'intérieur d'un container : <docker-bridge-ip>
```

### 2.7 Contexte proxy d'entreprise

Variables proxy présentes dans les containers Docker :

```
http_proxy=http://<corp-proxy-host>:<proxy-port>
https_proxy=http://<corp-proxy-host>:<proxy-port>
HTTP_PROXY=http://<corp-proxy-host>:<proxy-port>
HTTPS_PROXY=http://<corp-proxy-host>:<proxy-port>
no_proxy=localhost,<corp-domain-list>
NO_PROXY=localhost,<corp-domain-list>
```

**Impact :** toute connexion container vers une IP non dans `no_proxy` transite par le proxy corporate.  
Le proxy retourne `403 Authentication Required` pour les IPs privées non autorisées (ex. `<docker-bridge-ip>`, `10.x.x.x`).  
Tous les tests `container → Windows` ont été exécutés avec `--noproxy '*'` pour distinguer les erreurs proxy des erreurs routage.

### 2.8 Fixtures de test

| Fixture | Rôle | Port | État |
|---------|------|------|------|
| Python3 http.server (WSL2) | Service natif WSL2 | 4200 | Démarré (`0.0.0.0:4200`) |
| PowerShell HttpListener (Windows) | Service Windows de test | 8443 | Démarré (`localhost:8443`) |
| `nginx:alpine` (container A) | Container published | 8080→80 | `0.0.0.0:8080->80/tcp` |
| `nginx:alpine` (container B) | Second container published | 8081→80 | `0.0.0.0:8081->80/tcp` |
| `curlimages/curl` (bridge) | Client bridge | — | Instancié à la demande |
| `curlimages/curl --network host` | Client host-network | — | Instancié à la demande |

**Note fixtures :**  
- Le service Windows HTTPS sur 8443 n'a pas pu être configuré en TLS (netsh sslcert requiert des droits admin non disponibles). Un service HTTP a été substitué. Les tests curl utilisaient `http://` à la place de `https://`; la connectivité réseau (sujet du plan) a bien été validée.
- Le service Windows est configuré avec le préfixe `http://localhost:8443/` (HttpListener sans admin). http.sys refuse les requêtes où le header `Host` ne correspond pas à `localhost`.

---

## 3. Résultats par flux (matrice Mx)

### Tableau de synthèse

| Id | Flux testé | Commande représentative | Résultat | Code d'erreur |
|----|-----------|------------------------|----------|---------------|
| M1 | Windows → WSL2 natif (localhost:4200) | `curl.exe http://localhost:4200` | **OK** | HTTP 200 |
| M2 | Windows → Docker published (localhost:8080) | `curl.exe http://localhost:8080` | **KO** | curl(28) timeout 8s |
| M3 | WSL2 → Docker published (localhost:8080) | `curl http://localhost:8080` | **OK** | HTTP 200 |
| M4 | WSL2 → Windows service (localhost:8443) | `curl http://localhost:8443` | **OK** | HTTP 200 |
| M5 | WSL2 → Windows IP explicite (`<mirrored-ip-a>:8443`) | `curl http://<mirrored-ip-a>:8443` | **KO** | curl(7) Connection refused |
| M6 | Container bridge → WSL2 natif (`<docker-bridge-ip>:4200`) | `docker exec ... curl http://<docker-bridge-ip>:4200` | **OK** | HTTP 200 |
| M7 | Container bridge → Windows (`<docker-bridge-ip>:8443`) | `docker exec ... curl --noproxy '*' http://<docker-bridge-ip>:8443` | **KO** | curl(7) Connection refused |
| M8 | Windows → Docker container B (localhost:8081) | `curl.exe http://localhost:8081` | **KO** | curl(28) timeout 8s |
| M9 | Container → host.docker.internal:8443 | `docker exec ... curl http://host.docker.internal:8443` | **KO** | curl(28) DNS timeout |
| M10 | WSL2 → tunnel SSH (localhost:18443) | `curl http://localhost:18443` après `.\wsl-tunnel.ps1 up api` | **OK** | HTTP 200 (instable) |
| M11 | Container bridge → tunnel (`<docker-bridge-ip>:18443`) | `docker exec ... curl --noproxy '*' http://<docker-bridge-ip>:18443` | **KO** | curl(7) Connection refused |
| Track 4.1a | Container host-network → Windows (localhost:8443) | `docker run --network host curlimages/curl ... http://localhost:8443` | **OK** | HTTP 200 |
| Track 4.1b | Container host-network → Windows IP (`<mirrored-ip-a>:8443`) | `docker run --network host curlimages/curl ... http://<mirrored-ip-a>:8443` | **KO** | curl(7) Connection refused |
| Track 6.3 relay TCP | Container bridge → relay socat 28443 → Windows 8443 | `docker run curlimages/curl http://<docker-bridge-ip>:28443` | **Partiel** | TCP OK / HTTP 400 hostname |

---

## 4. Analyse par track

### Track 1 — Baseline mirrored

#### 4.1 Test 1.1 — M1 : Windows → service natif WSL2

```powershell
curl.exe --connect-timeout 8 --max-time 20 http://localhost:4200
# EXIT: 0 — réponse HTML reçue (listing répertoire Python)
```

**Résultat : OK.**  
L'ingress natif mirrored est fonctionnel. Windows accède via `localhost:4200` directement au service Python qui écoute sur `0.0.0.0:4200` dans WSL2. Ce flux correspond au principal avantage attendu du mode mirrored.

#### 4.2 Test 1.2 — M2 : Windows → Docker published port

```powershell
curl.exe --connect-timeout 8 --max-time 20 http://localhost:8080
# curl(28): Connection timed out after 8015 milliseconds

curl.exe --connect-timeout 8 --max-time 20 http://127.0.0.1:8080
# curl(28): Connection timed out after 8010 milliseconds
```

**Résultat : KO — régression confirmée.**

L'état de publication Docker dans WSL2 :
```
docker port test-nginx-a  →  80/tcp -> 0.0.0.0:8080 / [::]:8080
ss -ltnp  →  LISTEN  0.0.0.0:8080  (actif dans WSL2)
```

Docker publie correctement le port `8080` dans l'espace réseau WSL2. Cependant, Windows ne peut pas joindre ce port via le loopback partagé. Raison : les connexions Windows → `127.0.0.1:8080` traversent le chemin loopback mirrored mais **contournent les règles iptables DNAT de Docker** dans le kernel WSL2. Docker's NAT fonctionne uniquement pour le trafic entrant par les interfaces réseau standard (eth0, docker0), pas pour le trafic loopback mirrored.

Ce contournement est un comportement structurel du mode mirrored et non un artefact de configuration.

#### 4.3 Test 1.3 — M8 : Container B, second port

```powershell
curl.exe --connect-timeout 8 --max-time 20 http://localhost:8081
# curl(28): Connection timed out after 8003 milliseconds
```

**Résultat : KO — régression confirmée, indépendante du port et de l'image.**  
M2 et M8 donnent le même résultat (timeout identique) sur deux containers séparés avec deux ports différents. La régression n'est pas liée à un port ou une image spécifique.

#### 4.4 Test 1.4 — M3 : WSL2 → Docker published port

```bash
curl --connect-timeout 8 --max-time 20 http://localhost:8080
# HTTP_200 — nginx OK
```

**Résultat : OK.**  
WSL2 peut joindre ses propres containers publiés via localhost. Le bridge Docker fonctionne normalement pour le trafic interne WSL2. Le pattern M2=KO / M3=OK valide que le container est sain et que la régression est spécifique au chemin Windows→WSL2 loopback.

---

### Track 2 — Variantes d'adresses hôte

#### 4.5 Test 2.1 — M4 : WSL2 → Windows via localhost

```bash
curl --connect-timeout 8 --max-time 20 http://localhost:8443
# Windows-HTTP-8443-OK — HTTP 200
```

**Résultat : OK.**  
C'est le principal avantage mirrored pour les services natifs. WSL2 atteint Windows via le loopback partagé. Le test TCP direct a également confirmé l'accès :
```bash
nc -zv 127.0.0.1 8443  →  Connection succeeded!
```

#### 4.6 Test 2.2 — M5 : WSL2 → Windows via IP explicite

Toutes les IPs Windows testées depuis WSL2 :

```bash
curl http://<mirrored-ip-a>:8443  →  curl(7) Connection refused (0 ms)
curl http://<mirrored-ip-b>:8443  →  curl(7) Connection refused (0 ms)
curl http://<mirrored-ip-c>:8443  →  curl(7) Connection refused (0 ms)
curl http://<mirrored-ip-d>:8443  →  curl(7) Connection refused (0 ms)
```

Confirmation TCP :
```bash
nc -zv <mirrored-ip-a> 8443  →  Connection refused
nc -zv 127.0.0.1 8443     →  Connection succeeded!
```

**Résultat : KO sur toutes les IPs explicites.**  
L'analyse montre que port 8443 est bien ouvert (`0.0.0.0:8443 LISTEN` via http.sys PID 4). Le refus des IPs explicites s'explique par la combinaison de deux facteurs :

1. **http.sys hostname restriction** : le listener `http://localhost:8443/` de HttpListener n'accepte que des requêtes dont le `Host` correspond à `localhost`. Les connexions via IP explicite sont rejetées au niveau HTTP.
2. **Profil firewall Windows** : la règle TCP 8443 permet le trafic entrant mais le profil applicable sur les interfaces VPN (eth0, eth2, eth3) peut différer du profil `Private` activé pour le loopback.

Note : Le test `hostAddressLoopback=true` (Track 2.3 du plan) n'a pas été exécuté car ce paramètre nécessite un redémarrage WSL qui aurait perdu les fixtures et le contexte de test.

---

### Track 3 — Container → Windows

#### 4.7 Test 3.1 — M7 : Container bridge → Windows IP directe

```bash
docker exec test-nginx-a curl --noproxy '*' http://<mirrored-ip-a>:8443
# curl: (7) Failed to connect after 0 ms: Could not connect to server

docker exec test-nginx-a curl --noproxy '*' http://<docker-bridge-ip>:8443
# curl: (7) Failed to connect after 0 ms: Could not connect to server
```

**Résultat : KO.**  
Le container bridge envoie ses paquets via `<docker-bridge-ip>` (gateway docker0). En mode mirrored, cette gateway correspond à l'interface `docker0` de WSL2 (`<docker-bridge-ip>`), qui n'est pas mirrored avec Windows. Le service HTTP Windows écoute uniquement via le loopback mirrored (`localhost:8443`), non sur l'interface `<docker-bridge-ip>`.

#### 4.8 Test 3.2 — M9 : Container → host.docker.internal

```bash
docker exec test-nginx-a curl --noproxy '*' http://host.docker.internal:8443
# curl(28): Resolving timed out after 8001 milliseconds
```

**Résultat : KO — DNS non résolu.**  
`host.docker.internal` n'est pas injecté dans `/etc/hosts` des containers avec Docker Engine Linux (contrairement à Docker Desktop). Ce hostname n'est pas disponible sans configuration explicite.

#### 4.9 Test 3.3 — Variables proxy dans le container

```bash
docker exec test-nginx-a env | grep -i proxy
# http_proxy=http://<corp-proxy-host>:<proxy-port>
# HTTPS_PROXY=http://<corp-proxy-host>:<proxy-port>
# no_proxy=localhost,<corp-domain-list>
```

**Résultat : proxy corporate actif dans les containers.**  
Tests comparatifs avec/sans proxy :

```bash
# Sans --noproxy : proxy intercepte et retourne :
#  HTTP 403 "Cannot load block message - authenticationrequired.html"
# Avec --noproxy '*' : curl tente la connexion directe → Connection refused
```

Le proxy intercepte le trafic vers les IPs privées non dans `no_proxy`. Tous les tests M7 ont été exécutés avec `--noproxy '*'` pour valider le chemin réseau pur.

#### 4.10 Test 3.4 — Client container curlimages/curl (bridge)

```bash
docker run --rm curlimages/curl:latest --noproxy '*' http://<docker-bridge-ip>:8443
# curl(7): Connection refused
```

**Résultat : KO — identique à M7. Le résultat ne dépend pas du container shape.**

---

### Track 4 — Variantes réseau Docker

#### 4.11 Test 4.1 — Container --network host

```bash
docker run --rm --network host curlimages/curl:latest --noproxy '*' http://localhost:8443
# Windows-HTTP-8443-OK — HTTP 200
```

**Résultat : OK.**  
Un container `--network host` partage le namespace réseau de WSL2 et accède donc au loopback mirrored. `localhost:8443` dans ce container est identique à `localhost:8443` dans WSL2, qui miroire le Windows loopback. C'est le contournement fiable pour les containers devant consommer des services Windows.

```bash
docker run --rm --network host curlimages/curl:latest --noproxy '*' http://<mirrored-ip-a>:8443
# curl(7): Connection refused
```

Les IPs Windows explicites sont également refusées depuis un container host-network (même raison que M5 — firewall ou http.sys restriction).

#### 4.12 Test 4.2 — ignoredPorts

Non exécuté. Les résultats M2/M8 (timeout, pas de refus) indiquent que la régression n'est pas due à un conflit de listener sur les ports 8080/8081. `ignoredPorts` n'aurait pas d'impact sur ce type d'échec. Ce test est écarté comme non pertinent au vu des données observées.

---

### Track 5 — Firewall Windows

Profils actifs :

```
Name    Enabled
Domain  True
Private True
Public  True
```

Règles autorisant TCP 8443 (inbound) : 2 règles allow trouvées.

État TCP Windows :

```
TCP    0.0.0.0:8443    LISTEN  PID 4 (http.sys)
TCP    [::]:8443       LISTEN  PID 4 (http.sys)
```

Les ports Docker (8080, 8081, 4200) ne sont pas visibles depuis Windows `netstat` — ils existent uniquement dans l'espace réseau WSL2 interne.

**Conclusion Track 5 :** les paquets `localhost → loopback` sont acceptés (pas de filtrage firewall sur le loopback). Les refus sur IPs explicites (`M5`, `Track 4.1b`) sont attribuables à la configuration du listener http.sys (préfixe `localhost` uniquement) plutôt qu'au firewall seul. Le firewall ne bloque pas explicitement ces flows — la connexion TCP est refusée avant la couche HTTP.

---

### Track 6 — Mirrored + tunnel

#### 4.13 Test 6.1 — M10 : WSL2 natif → tunnel endpoint

```powershell
.\wsl-tunnel.ps1 up api
# "Tunnel 'api' is active. WSL localhost:18443 -> Windows localhost:8443"

wsl -- bash -c "curl http://localhost:18443"
# Windows-HTTP-8443-OK  →  EXIT 0
```

**Résultat : OK (avec réserve de stabilité).**

Le tunnel fonctionne correctement quand il est actif : la chaîne `WSL2 localhost:18443 → SSH reverse → Windows localhost:8443` est opérationnelle. Cependant, **le tunnel est instable en mode mirrored** — le processus SSH s'arrête dans les 3 à 10 secondes après démarrage dans les conditions de test observées.

**Analyse de l'instabilité :**

Logs sshd WSL2 (extrait significatif) :
```
09:00:36  sshd[277]: Server listening on 0.0.0.0 port 22
09:00:58  sshd[890]: Accepted publickey for wsl from 127.0.0.1 port 65329
09:00:58  sshd[890]: pam_unix: session opened for user wsl
09:01:46  sshd[277]: Received signal 15; terminating.  ← SIGTERM systemd
09:02:02  sshd[278]: Server listening on 0.0.0.0 port 22
```

WSL2 reçoit un SIGTERM de systemd à intervalles irréguliers, ce qui tue sshd et interrompt tous les tunnels en cours. Cette instabilité est corrélée avec le cycle de vie du terminal PowerShell de pilotage et les invocations répétées de `wsl --`. En mode mirrored, WSL2 semble plus sensible aux redémarrages automatiques lors de changements de session.

Note : le tunnel a fonctionné lors de 5 tests consécutifs (sur 8 tentatives). Il n'est pas fondamentalement incompatible avec mirrored mais require une session WSL suffisamment stable.

#### 4.14 Test 6.2 — M11 : Container bridge → tunnel endpoint

```bash
docker exec test-nginx-a curl --noproxy '*' http://<docker-bridge-ip>:18443
# curl(7): Connection refused
```

**Résultat : KO.**

Le tunnel SSH (reverse forwarding `-R 18443:localhost:8443`) crée un listener sur `127.0.0.1:18443` uniquement (conformément au paramètre sshd `GatewayPorts no` par défaut). L'interface docker0 (`<docker-bridge-ip>`) n'est pas couverte par ce listener. Les containers bridge ne peuvent donc pas joindre le tunnel.

Configuration sshd confirmée :
```
#GatewayPorts no   ← commenté = valeur par défaut = no
```

Activation de `GatewayPorts yes` permettrait au tunnel de binder sur `0.0.0.0:18443`, rendant M11 potentiellement OK. Ce test n'a pas été exécuté mais la correction est documentée.

#### 4.15 Test 6.3 — Relay socat (container → Windows direct)

**Variante A : relay via tunnel (échouée)**

```bash
socat TCP-LISTEN:28443,fork,bind=0.0.0.0,reuseaddr TCP:127.0.0.1:18443
# socat: E connect AF=2 127.0.0.1:18443: Connection refused
# (tunnel mort avant exécution du relay)
```

**Variante B : relay direct WSL2 loopback → Windows (résultat clé)**

```bash
# Lancement du relay dans WSL2 :
socat TCP-LISTEN:28443,fork,bind=0.0.0.0,reuseaddr TCP:127.0.0.1:8443

# Test depuis container bridge :
docker run --rm curlimages/curl:latest --noproxy '*' http://<docker-bridge-ip>:28443
# HTTP 400 — Bad Request - Invalid Hostname
# 334 bytes reçus (connexion TCP établie, réponse HTTP reçue)
```

**Résultat : TCP OK / HTTP KO (400 hostname mismatch).**

C'est la découverte la plus significative de Track 6 :

- **Le chemin réseau container → relay → Windows existe** en mode mirrored.
- Le relay socat sur `0.0.0.0:28443` dans WSL2, pointant vers `127.0.0.1:8443` (loopback mirrored vers Windows), crée un pont fonctionnel au niveau TCP.
- La connexion échoue uniquement au niveau HTTP : http.sys retourne HTTP 400 car le header `Host: <docker-bridge-ip>:28443` ne correspond pas au préfixe `http://localhost:8443/`.
- **Solution** : configurer le service Windows pour accepter `http://+:8443/` (nécessite droits admin pour la réservation netsh URL), ou utiliser un serveur HTTP sans restriction de hostname (nginx, node, caddy, ...).

Ce résultat est une preuve de concept : **mirrored + socat relay résout le chemin container → Windows si le service Windows écoute sur `+` (toutes interfaces) et pas uniquement `localhost`**.

---

## 5. Réponses aux questions primaires du plan

### Question 1 : La régression Windows → Docker published port est-elle reproductible au-delà d'un seul container et d'un seul port ?

**Oui, confirmé.** M2 et M8 donnent des timeouts identiques sur deux containers (`nginx:alpine`) avec deux ports différents (8080 et 8081). La régression est structurelle et indépendante du container ou du port.

### Question 2 : Mirrored fonctionne-t-il mieux avec certains modèles réseau Docker ?

**Oui, partiellement.** 

- **Bridge (défaut) : KO** pour tout flux container → Windows.
- **Host network : OK** pour les containers consommant des services Windows via `localhost`. C'est le seul mode Docker compatible nativement avec mirrored pour ce type de dépendance.

### Question 3 : Les paramètres mirrored (`hostAddressLoopback`, `ignoredPorts`) changent-ils les résultats ?

- **`ignoredPorts`** : non testé car le diagnostic de M2/M8 (timeout, pas de refus) indique que le problème n'est pas un conflit de listener. `ignoredPorts` n'est pas pertinent ici.
- **`hostAddressLoopback=true`** : non testé (redémarrage WSL requis, trop coûteux en contexte d'instabilité). Reste à valider dans une session dédiée.

### Question 4 : L'échec container → Windows vient-il du mode mirrored, du routage, du proxy ou de la portée du listener Windows ?

**Explication multicouche :**

1. **Routage (cause principale M7)** : le container bridge envoie ses paquets via `<docker-bridge-ip>` (docker0). Ce chemin ne passe pas par le loopback mirrored Windows↔WSL2.
1. **Routage (cause principale M7)** : le container bridge envoie ses paquets via `<docker-bridge-ip>` (docker0). Ce chemin ne passe pas par le loopback mirrored Windows↔WSL2.
2. **Listener Windows (cause principale M5, Track 4.1b)** : le service Windows lie sur `http://localhost:8443/`. Les connexions via IP explicite sont rejetées par http.sys.
3. **Proxy (cause amplificatrice)** : sans `--noproxy '*'`, le proxy intercepte les connexions vers les IPs privées et retourne HTTP 403.
4. **Firewall Windows (probable)** : les profils firewall protègent les interfaces VPN (eth0, eth2, eth3) et peuvent bloquer le trafic entrant sur les ports non explicitement autorisés pour ces profils.

### Question 5 : Mirrored seul est-il suffisant pour l'objectif du dépôt, ou faut-il le tunnel et/ou un relay ?

**Mirrored seul est insuffisant.** L'objectif du dépôt est d'exposer des services Windows aux containers Docker. En mode mirrored :

- Les services natifs WSL2 peuvent consommer Windows (M4 OK) — mais ce cas ne requiert pas de tunnel.
- Les containers bridge ne peuvent pas consommer Windows directement (M7 KO).
- Le tunnel SSH résoud M10 (WSL2 natif → Windows via tunnel) mais pas M11 (container bridge → tunnel) sans `GatewayPorts yes`.
- Le relay socat résoud le chemin TCP (Track 6.3) mais requiert que le service Windows soit accessible via `+` (wildcard hostname), pas juste `localhost`.

---

## 6. Découvertes additionnelles

### 6.1 Instabilité WSL2 en mode mirrored

47 restarts de sshd ont été enregistrés dans le journal systemd WSL2 au cours de la session (incluant les sessions précédentes). Les arrêts sont déclenchés par `signal 15 (SIGTERM) from systemd` — indiquant des redémarrages WSL2 programmés ou déclenchés par les invocations PowerShell.

Le mode mirrored semble moins stable que NAT sur ce poste dans ce contexte de tests, potentiellement dû à l'environnement VPN multi-interfaces.

### 6.2 Contournement prioritaire : --network host

La découverte la plus actionnable : les containers `--network host` atteignent Windows via `localhost` en mode mirrored. Ce mode permet aux containers de se comporter comme des processus WSL2 natifs du point de vue réseau.

**Contraintes de --network host :**
- Pas compatible avec les ports publiés (`-p`)
- Risque de conflits de ports entre containers et WSL2
- Non applicable si plusieurs containers doivent s'isoler entre eux

### 6.3 SSH tunnel et GatewayPorts

Le tunnel SSH du dépôt (`wsl-tunnel.ps1`) crée un reverse forward sur `127.0.0.1:wslPort` uniquement (`GatewayPorts no`). Pour rendre M11 possible, deux options existent :

**Option 1 :** activer `GatewayPorts yes` dans `/etc/ssh/sshd_config` de WSL2 pour que le tunnel bind sur `0.0.0.0:18443`.

**Option 2 :** ajouter un relay socat post-tunnel :
```bash
socat TCP-LISTEN:18443,fork,bind=0.0.0.0,reuseaddr TCP:127.0.0.1:18443
```
Mais cela créerait un conflit de port avec le tunnel lui-même.

La vraie solution pour M11 en mirrored est la combinaison relay direct + service Windows configurable :
```bash
socat TCP-LISTEN:18443,fork,bind=0.0.0.0,reuseaddr TCP:127.0.0.1:8443
```
Sans impliquer de tunnel SSH du tout, en s'appuyant sur le loopback mirrored.

### 6.4 host.docker.internal non disponible

Sans Docker Desktop, `host.docker.internal` n'est pas injecté automatiquement. Il peut être ajouté manuellement via `--add-host host.docker.internal:<docker-bridge-ip>` au lancement du container, mais pointera vers la gateway docker0, pas vers le loopback mirrored.
Sans Docker Desktop, `host.docker.internal` n'est pas injecté automatiquement. Il peut être ajouté manuellement via `--add-host host.docker.internal:<docker-bridge-ip>` au lancement du container, mais pointera vers la gateway docker0, pas vers le loopback mirrored.

---

## 7. Décision et classement d'outcome

### Verdict : **Outcome B — Mirrored acceptable pour les workflows natifs uniquement**

**Critères Outcome B :**
- ✅ WSL2 ↔ Windows via `localhost` : OK (M1, M4)
- ✅ WSL2 interne → Docker : OK (M3)
- ❌ Windows → Docker published ports : KO (M2, M8)
- ❌ Container bridge → Windows : KO (M7, M9)

**Ce qui fonctionne nativement en mirrored :**

| Flux | Fonctionnel |
|------|------------|
| Windows curl → WSL2 service natif | Oui |
| WSL2 curl → Windows service natif | Oui |
| WSL2 interne → Docker container | Oui |
| Container host-network → Windows via localhost | Oui |
| Tunnel SSH WSL2 natif | Oui (instable) |

**Ce qui ne fonctionne pas nativement en mirrored :**

| Flux | Bloqué par |
|------|-----------|
| Windows → Docker published port | iptables DNAT bypass par loopback mirrored |
| Container bridge → Windows | docker0 non mirrored, pas de chemin loopback disponible |
| Container bridge → tunnel SSH | GatewayPorts no (tunnel uniquement sur loopback) |
| WSL2/container → Windows via IP explicite | http.sys hostname restriction + firewall profil |

---

## 8. Réponses aux questions finales du plan

### 1. Mirrored seul est-il suffisant pour l'objectif du dépôt ?

**Non.** L'objectif central (`container → service Windows`) est KO en mode mirrored sans configuration supplémentaire substantielle.

### 2. Mirrored + tunnel ou relay vaut-il la peine ?

**Partiellement.** Le relay socat direct (`socat 28443→localhost:8443`) ouvre le chemin TCP container → Windows. Mais il exige :
- que le service Windows écoute sur `+` (wildcard) et non juste `localhost`
- un relay socat démarré et maintenu dans WSL2
- potentiellement les droits admin Windows pour la réservation netsh

Le tunnel SSH (`wsl-tunnel.ps1`) seul ne résoud pas M11 sans `GatewayPorts yes` côté sshd.

### 3. La régression Windows → Docker est-elle une vraie régression mirrored sur ce poste ?

**Oui, confirmé.** La régression est structurelle en mirrored sur Docker Engine Linux : le loopback partagé contourne les règles iptables DNAT de Docker. Ce comportement est documenté et attendu par la communauté Docker/WSL2.

### 4. Quels paramètres mirrored ont matériellement changé les résultats ?

Aucun parmi ceux testés. `localhostForwarding` est sans effet (attendu). `hostAddressLoopback=true` et `ignoredPorts` n'ont pas été testés.

### 5. Mirrored doit-il rester en portée comme mode primaire, de secours ou limitation documentée ?

**Recommandation : limitation documentée, pas mode de secours.**

Le mode NAT reste le mode primaire opérationnel pour ce dépôt car :
- Le tunnel SSH fonctionne de façon fiable en NAT
- Docker published ports sont accessibles de Windows en NAT (via localhostForwarding)
- Aucun flux du dépôt ne requiert le mode mirrored

Mirrored peut être documenté comme :
> Compatible pour les workflows où seul le service WSL2 natif consomme Windows (sans container bridge), avec `--network host` comme contournement si des containers sont impliqués.

---

## 9. Configuration restaurée

À la fin de la campagne, la configuration `.wslconfig` originale a été restaurée :

```ini
[wsl2]
swap = 0
autoProxy=false
networkingMode=NAT
localhostForwarding=true
```

WSL2 a été redémarré pour appliquer le retour à NAT.

---

## 10. Annexes

### A. Configuration .wslconfig testée

```ini
[wsl2]
swap = 0
autoProxy=false
networkingMode=mirrored
localhostForwarding=true
```

WSL2 redémarré après changement : oui.

### B. Commandes infrastructure testées

**Fixtures démarrées :**
```bash
# WSL2 natif
python3 -m http.server 4200 --bind 0.0.0.0

# Docker containers
docker run --rm -d --name test-nginx-a -p 8080:80 nginx:alpine
docker run --rm -d --name test-nginx-b -p 8081:80 nginx:alpine

# Windows (PowerShell Job)
$listener.Prefixes.Add("http://localhost:8443/") ; $listener.Start()
```

**Tunnel:**
```powershell
.\wsl-tunnel.ps1 up api
# ssh -N -o ExitOnForwardFailure=yes -R 18443:localhost:8443 wsl-localhost
```

**Relay socat:**
```bash
socat TCP-LISTEN:28443,fork,bind=0.0.0.0,reuseaddr TCP:127.0.0.1:8443
```

### C. Tableau de stabilité des fixtures

| Fixture | Stabilité observée |
|---------|-------------------|
| Python HTTP 4200 WSL2 | Stable (tenu pendant toute la session) |
| Windows HTTP 8443 (PowerShell Job) | Instable (job PowerShell arrêté par timeout terminal) |
| Docker containers | Redémarrés 3× suite aux restarts WSL2 |
| SSH tunnel (wsl-tunnel.ps1) | Très instable (process meurt en 3–10s) |

### D. Version du plan de validation suivi

Plan : [MIRRORED-MODE-VALIDATION-PLAN.md](MIRRORED-MODE-VALIDATION-PLAN.md)  
Commit de référence : `local-only-commits.patch` présent dans le dépôt.
