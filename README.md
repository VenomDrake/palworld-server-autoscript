# Palworld Server Autoscript

Script Bash per Proxmox VE in stile Community Scripts che crea automaticamente un container LXC Ubuntu per un **Palworld Dedicated Server** gestito tramite **LinuxGSM** (`pwserver`).

## Cosa fa lo script

`palworld.sh` usa il framework `build.func` dei Community Scripts come base tecnica per creare un container LXC Proxmox VE, ma il progetto è un installer indipendente con identità visuale propria: **Palworld Server Autoscript**. Dopo la creazione del container configura automaticamente Palworld all'interno del container con LinuxGSM.

In particolare:

- crea un LXC Ubuntu 22.04 con CTID automatico, cioè il primo ID disponibile scelto dal framework;
- usa hostname predefinito `palworld`;
- configura risorse predefinite di 4 CPU, 8192 MiB RAM e 40 GB disco;
- crea un container unprivileged di default;
- installa dipendenze LinuxGSM/SteamCMD per Ubuntu 22.04, incluse librerie i386 richieste;
- tenta l'installazione di `steamcmd` dai repository Ubuntu, se disponibile;
- crea l'utente dedicato `pwserver`;
- chiede il nome pubblico del server Palworld con default `Palworld Server`;
- scarica LinuxGSM con `curl -Lo linuxgsm.sh https://linuxgsm.sh` ed esegue `bash linuxgsm.sh pwserver`;
- installa Palworld Dedicated Server tramite LinuxGSM con `./pwserver auto-install`, con fallback a `./pwserver install` non interattivo;
- crea e abilita il servizio systemd `pwserver.service`;
- avvia il server al termine dell'installazione;
- configura cron come utente `pwserver` per monitoraggio, update del server e update periodico di LinuxGSM.

LinuxGSM gestisce Palworld tramite il comando/server script `pwserver`. L'AppID Steam del Palworld Dedicated Server è `2394010`.

## Identità visuale e framework

Questo progetto mantiene una propria identità visuale nel wizard: **Palworld Server Autoscript**. Le schermate iniziali e le opzioni visibili vengono personalizzate localmente dallo script, mentre `build.func` dei Community Scripts resta usato solo come framework tecnico per la creazione del container LXC.

## Installazione

Esegui questo comando nella shell del nodo Proxmox VE:

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/VenomDrake/palworld-server-autoscript/main/palworld.sh)"
```

## Requisiti Proxmox VE

- Proxmox VE con supporto LXC funzionante.
- Accesso root alla shell del nodo Proxmox VE.
- Accesso Internet dal nodo Proxmox VE e dal container LXC.
- Storage Proxmox configurato per template LXC e rootdir.
- Bridge di rete Proxmox configurato, normalmente `vmbr0`.
- DHCP raggiungibile oppure configurazione statica durante il wizard Community Scripts.

## Risorse consigliate

Default dello script:

| Risorsa | Valore |
| --- | ---: |
| CPU | 4 core |
| RAM | 8192 MiB |
| Disco | 40 GB |
| OS | Ubuntu 22.04 |
| Tipo container | Unprivileged |

Per server con molti giocatori, mondi pesanti, mod o backup frequenti, valuta più RAM, più CPU e più spazio disco.

## Porte da aprire

Porte predefinite LinuxGSM/Palworld da aprire o inoltrare sul router/firewall verso l'IP del container:

| Porta | Protocollo | Uso |
| --- | --- | --- |
| 8211 | UDP | Porta gioco Palworld |
| 27015 | UDP | Porta Steam query configurata da LinuxGSM |

Note:

- `27016/udp` non è una porta predefinita dell'attuale configurazione LinuxGSM per `pwserver`; usala solo se modifichi la `queryport`/`steamport` in LinuxGSM.
- `25575/tcp` è da aprire solo se abiliti RCON nella configurazione Palworld.
- Dopo l'installazione, verifica sempre le porte reali con `./pwserver details`.

## Nome pubblico del server

Durante il wizard lo script mostra il prompt **Palworld Server Name** con default `Palworld Server`. Il valore scelto viene scritto nell'override locale LinuxGSM:

```text
/home/pwserver/lgsm/config-lgsm/pwserver/pwserver.cfg
```

In questo modo i parametri di avvio usano `-servername='<nome scelto>'` invece del default LinuxGSM.

## Password e accessi

Durante l'installazione vengono gestite due password diverse:

- **root password**: è la password dell'utente `root` del container LXC. Viene gestita dal wizard standard basato su Community Scripts e non viene modificata dallo script Palworld.
- **pwserver password**: è la password dell'utente Linux dedicato `pwserver`, usato per gestire LinuxGSM e Palworld. Lo script Palworld la richiede con una schermata dedicata; se lasci il campo vuoto, viene generata automaticamente una password sicura e mostrata solo nel riepilogo finale.

Per accedere all'utente LinuxGSM dopo l'installazione:

```bash
su - pwserver
```

Per verificare lo stato del servizio Palworld:

```bash
systemctl status pwserver
```

## Percorsi principali

| Scopo | Percorso |
| --- | --- |
| Home/LinuxGSM | `/home/pwserver` |
| Script LinuxGSM | `/home/pwserver/pwserver` |
| File server Palworld | `/home/pwserver/serverfiles` |
| Config Palworld | `/home/pwserver/serverfiles/Pal/Saved/Config/LinuxServer/PalWorldSettings.ini` |
| Config LinuxGSM istanza | `/home/pwserver/lgsm/config-lgsm/pwserver/pwserver.cfg` |
| Log LinuxGSM | `/home/pwserver/log` |
| Log gioco Palworld | `/home/pwserver/serverfiles/Pal/Saved/Logs` |

## Comandi LinuxGSM utili

Entra come utente dedicato:

```bash
su - pwserver
```

Poi usa i comandi LinuxGSM:

```bash
./pwserver details
./pwserver console
./pwserver restart
./pwserver update
./pwserver force-update
./pwserver validate
./pwserver monitor
./pwserver update-lgsm
```

## Aggiornare il server

Aggiornamento manuale:

```bash
su - pwserver
./pwserver update
./pwserver restart
```

Validazione dei file server SteamCMD:

```bash
su - pwserver
./pwserver validate
```

Lo script configura anche questi cron per l'utente `pwserver`:

```cron
*/5 * * * * /home/pwserver/pwserver monitor >/dev/null 2>&1
30 4 * * * /home/pwserver/pwserver update >/dev/null 2>&1
0 0 * * 0 /home/pwserver/pwserver update-lgsm >/dev/null 2>&1
```

## Test post installazione

Dopo la creazione del container e l'avvio finale, entra nel container oppure usa la console Proxmox e verifica lo stato del servizio:

```bash
systemctl status pwserver
```

Per ulteriori dettagli operativi usa anche:

```bash
su - pwserver
./pwserver details
```

## Vedere dettagli, porte e password

Per visualizzare dettagli del server, password, porte, file di configurazione e percorsi:

```bash
su - pwserver
./pwserver details
```

Per aprire la console LinuxGSM del server:

```bash
su - pwserver
./pwserver console
```

Per uscire dalla console senza fermare il server usa `CTRL+b`, poi `d`.

## Configurare Palworld

Il file principale di configurazione Palworld è:

```text
/home/pwserver/serverfiles/Pal/Saved/Config/LinuxServer/PalWorldSettings.ini
```

Suggerimenti:

1. Ferma il server prima di modificare la configurazione.
2. Modifica `PalWorldSettings.ini` mantenendo il formato richiesto da Palworld.
3. Riavvia il server con `./pwserver restart`.
4. Controlla `./pwserver details` e i log se le modifiche non vengono applicate.

## Servizio systemd

Il server viene gestito anche dal servizio systemd `pwserver.service`:

```bash
systemctl status pwserver.service
systemctl restart pwserver.service
systemctl stop pwserver.service
systemctl start pwserver.service
```

Il servizio è abilitato all'avvio del container. LinuxGSM avvia il server in `tmux`; il monitoraggio periodico è gestito dal cron dell'utente `pwserver`.

## Known limitations

- Il primo avvio di Palworld può richiedere diversi minuti, soprattutto dopo installazione, update o validazione dei file server.
- Il server potrebbe non comparire subito nella lista pubblica: attendi qualche minuto e verifica prima con connessione diretta tramite IP/porta.
- Se usi NAT, devi aprire/inoltrare `8211/udp` e `27015/udp` sul router verso l'IP del container.
- RCON è opzionale e va configurato manualmente nella configurazione Palworld prima di aprire eventuali porte dedicate.
- LXC unprivileged è il default consigliato dallo script; tuttavia eventuali problemi specifici SteamCMD/Palworld potrebbero richiedere test comparativi su container privileged o su VM.
