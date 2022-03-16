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

### Utilizzo

Se si vuole ottenere il certificato e la configurazione senza alterare il sistema:

```console
$ make create-pfext01-step-openvpn
```

Invece per creare ed importare automaticamente la VPN nel NetworkManager tramite `nmcli`:

```console
$ make import-pfext01-step-openvpn
```

Per avviare la VPN da riga di comando (comunque accessibile anche dalla GUI del NetworkManager):

```console
$ nmcli con up confinet-pfext01-step
```

Per importare il certificato in Firefox (Linux) accertarsi di avere installato il pacchetto `libnss3-tools` e poi:

```console
$ make import-p12-into-firefox
```

Si può concatenare al comando della VPN:

```console
$ make import-pfext01-step-openvpn import-p12-into-firefox
```

Per la selezione automatica del certificato su Firefox, modificare queste due impostazioni in `about:config`:

```
security.default_personal_cert                    => Select Automatically
security.remember_cert_checkbox_default_setting   => false
```

Dovreste quindi vederle nel `pref.js` del vostro profilo Firefox:

```console
$ grep cert ~/.mozilla/firefox/*/prefs.js 
user_pref("security.default_personal_cert", "Select Automatically");
user_pref("security.remember_cert_checkbox_default_setting", false);
```
