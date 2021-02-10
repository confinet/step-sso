## Confinet STEP SSO

Questo repository consente alle utenze @confinet.it di acquisire un
certificato giornaliero per accedere alle risorse aziendali.

### Installazione

Con GIT (preferibile per facilitare gli aggiornamenti):

```
git clone https://github.com/confinet/step-sso.git confinet-step-sso \
    && cd confinet-step-sso
```

Senza GIT:

```
wget -O confinet-step-sso.zip "https://github.com/confinet/step-sso/archive/master.zip" \
  && unzip -o confinet-step-sso.zip \
  && mv step-sso-master confinet-step-sso \
  && cd confinet-step-sso
```

### Comandi disponibili

```
$ make
Comandi disponibili:
create-pfext01-step-openvpn    Crea configurazione VPN in data/pfext01-step.ovpn
import-pfext01-step-openvpn    Crea ed Importa configurazione VPN nel NetworkManager tramite `nmcli`
encrypt-configs                Cifra le configurazioni modificate
```
