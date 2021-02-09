.DELETE_ON_ERROR:

STEP_VERSION=0.15.3

export STEPPATH=${PWD}/data/.step

.PHONY: help
help:
	@echo "Comandi disponibili:"
	@grep -E '^[a-zA-Z0-9_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[32m%-30s\033[0m %s\n", $$1, $$2}'

data/step-${STEP_VERSION}.tgz:
	rm -frv data/step*
	wget -O data/step-${STEP_VERSION}.tgz https://github.com/smallstep/cli/releases/download/v${STEP_VERSION}/step_linux_${STEP_VERSION}_amd64.tar.gz
	tar -C data -xf data/step-${STEP_VERSION}.tgz
	ln -s step_${STEP_VERSION}/bin/step data/step

data/step: data/step-${STEP_VERSION}.tgz

configs-plain/files.tar: data/step configs-cipher/files.tar.jwe
	data/step crypto jwe decrypt \
		< configs-cipher/files.tar.jwe \
		> configs-plain/files.tar
	tar xv \
		--directory configs-plain/ \
		--file configs-plain/files.tar

data/.step/config/defaults.json: data/step-${STEP_VERSION}.tgz configs-plain/files.tar
	data/step ca bootstrap --force \
		--ca-url $(file < configs-plain/ca-url) \
		--fingerprint  $(file < configs-plain/ca-fingerprint)

data/user_email:
	systemd-ask-password --echo "Inserisci la tua email Confinet:" > data/user_email

data/TOKEN: data/.step/config/defaults.json configs-plain/files.tar data/user_email
	step oauth \
		--oidc \
		--bare \
		--client-id $(file < configs-plain/client-id) \
		--client-secret $(file < configs-plain/client-secret) \
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

data/pfext01-step.ovpn: data/.step/config/defaults.json data/.step/user.crt configs-plain/files.tar
	cp -a configs-plain/pfext01-step.ovpn data/pfext01-step.ovpn.tmp
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

.PHONY: encrypt-configs
encrypt-configs: data/step ## Cifra le configurazioni modificate
	tar cvp \
		--directory configs-plain/ \
		--file configs-plain/files.tar \
		--exclude ./files.tar \
		--exclude ./.gitignore \
		./
	data/step crypto jwe encrypt --alg PBES2-HS512+A256KW \
		< configs-plain/files.tar \
		> configs-cipher/files.tar.jwe
	rm configs-plain/files.tar

.PHONY: clean
clean:
	rm -frv data/* data/.step
