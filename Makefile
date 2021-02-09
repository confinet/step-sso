STEP_VERSION=0.15.3

export STEPPATH=${PWD}/data/.step

.PHONY: help
help:
	@echo "Comandi disponibili:"
	@grep -E '^[a-zA-Z0-9_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[32m%-30s\033[0m %s\n", $$1, $$2}'

data/step-${STEP_VERSION}.tgz:
	rm -frv data/step*
	wget -O data/step-${STEP_VERSION}.tgz https://github.com/smallstep/cli/releases/download/v${STEP_VERSION}/step_linux_${STEP_VERSION}_amd64.tar.gz
	tar -C data -xf data/step-${STEP_VERSION}.tgz
	ln -s step_${STEP_VERSION}/bin/step data/step

data/.step/config/defaults.json: data/step-${STEP_VERSION}.tgz
	data/step ca bootstrap --force \
		--ca-url $(file < configs/ca-url) \
		--fingerprint  $(file < configs/ca-fingerprint)

data/user_email:
	systemd-ask-password --echo "Inserisci la tua email Confinet:" > data/user_email

data/TOKEN: data/.step/config/defaults.json
	rm -f data/TOKEN
	step oauth \
		--oidc \
		--bare \
		--client-id $(file < configs/client-id) \
		--client-secret $(file < configs/client-secret) \
		--email $(file < data/user_email) \
		> data/TOKEN

data/.step/user.crt: data/user_email data/TOKEN
	data/step ca certificate --force \
		--token $(file < data/TOKEN) \
		--kty RSA \
		--size 2048 \
		$(file < data/user_email) \
		data/.step/user.crt \
		data/.step/user.key
	rm -f data/TOKEN

data/pfext01-step.ovpn: data/.step/user.crt
	cp -a configs/pfext01-step.ovpn data/pfext01-step.ovpn.tmp
	echo "<ca>"                         >> data/pfext01-step.ovpn.tmp
	cat data/.step/certs/root_ca.crt    >> data/pfext01-step.ovpn.tmp
	echo "</ca>"                        >> data/pfext01-step.ovpn.tmp
	echo "<cert>"                       >> data/pfext01-step.ovpn.tmp
	cat data/.step/user.crt             >> data/pfext01-step.ovpn.tmp
	echo "</cert>"                      >> data/pfext01-step.ovpn.tmp
	echo "<key>"                        >> data/pfext01-step.ovpn.tmp
	cat data/.step/user.key             >> data/pfext01-step.ovpn.tmp
	echo "</key>"                       >> data/pfext01-step.ovpn.tmp
	mv data/pfext01-step.ovpn.tmp data/pfext01-step.ovpn

.PHONY: import-pfext01-step-openvpn
create-pfext01-step-openvpn: data/pfext01-step.ovpn ## Crea configurazione VPN in data/pfext01-step.ovpn

.PHONY: import-pfext01-step-openvpn
import-pfext01-step-openvpn: data/pfext01-step.ovpn ## Importa configurazione VPN nel NetworkManager tramite `nmcli`
	-nmcli connection delete pfext01-step
	nmcli connection import type openvpn file data/pfext01-step.ovpn
	-echo -e "set ipv4.never-default yes\nsave\nquit" \
		| nmcli connection edit pfext01-step

ok: data/pfext01-step.ovpn
	data/step

.PHONY: clean
clean:
	rm -frv data/* data/.step
