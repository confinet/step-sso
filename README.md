## Confinet STEP SSO

Questo repository consente alle utenze `@confinet.it` di acquisire un
certificato giornaliero per accedere alle risorse aziendali.

### Installazione

Con GIT (preferibile per facilitare gli aggiornamenti):

```
$ git clone https://github.com/confinet/step-sso.git confinet-step-sso \
    && cd confinet-step-sso
```

Senza GIT:

```
$ wget -O confinet-step-sso.zip "https://github.com/confinet/step-sso/archive/master.zip" \
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

### Utilizzo

Se si vuole ottenere il certificato e la configurazione senza alterare il sistema:

```
$ make --directory=/path/to/confinet-step-sso create-pfext01-step-openvpn
```

Invece per creare ed importare automaticamente la VPN nel NetworkManager tramite `nmcli`:

```
$ make --directory=/path/to/confinet-step-sso import-pfext01-step-openvpn
$ # Per avviare la VPN da riga di comando (comunque accessibile anche dalla GUI del NetworkManager):
$ nmcli con up confinet-pfext01-step
```
