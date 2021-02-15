.DELETE_ON_ERROR:

BUILD_DIR := .
STEP_VERSION := 0.15.3

export STEPPATH=$(BUILD_DIR)/data/.step

.PHONY: help
help:
	@echo "Comandi disponibili:"
	@grep -E '^[a-zA-Z0-9_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[32m%-30s\033[0m %s\n", $$1, $$2}'

data/step-$(STEP_VERSION).tgz:
	rm -frv $(BUILD_DIR)/data/step*
	wget -O $(BUILD_DIR)/data/step-$(STEP_VERSION).tgz https://github.com/smallstep/cli/releases/download/v$(STEP_VERSION)/step_linux_$(STEP_VERSION)_amd64.tar.gz
	tar -C $(BUILD_DIR)/data -xf $(BUILD_DIR)/data/step-$(STEP_VERSION).tgz
	ln -s step_$(STEP_VERSION)/bin/step $(BUILD_DIR)/data/step

data/step: data/step-$(STEP_VERSION).tgz

configs-plain/files.tar: data/step configs-cipher/files.tar.jwe
	$(BUILD_DIR)/data/step crypto jwe decrypt \
		< $(BUILD_DIR)/configs-cipher/files.tar.jwe \
		> $(BUILD_DIR)/configs-plain/files.tar
	tar xv \
		--directory $(BUILD_DIR)/configs-plain/ \
		--file $(BUILD_DIR)/configs-plain/files.tar

data/.step/config/defaults.json: data/step-$(STEP_VERSION).tgz configs-plain/files.tar
	$(BUILD_DIR)/data/step ca bootstrap --force \
		--ca-url $(shell cat $(BUILD_DIR)/configs-plain/ca-url) \
		--fingerprint  $(shell cat $(BUILD_DIR)/configs-plain/ca-fingerprint)

data/user_email:
	systemd-ask-password --echo "Inserisci la tua email Confinet:" > $(BUILD_DIR)/data/user_email

data/TOKEN: data/.step/config/defaults.json configs-plain/files.tar data/user_email
	$(BUILD_DIR)/data/step oauth \
		--oidc \
		--bare \
		--client-id $(shell cat $(BUILD_DIR)/configs-plain/client-id) \
		--client-secret $(shell cat $(BUILD_DIR)/configs-plain/client-secret) \
		--email $(shell cat $(BUILD_DIR)/data/user_email) \
		> $(BUILD_DIR)/data/TOKEN

data/.step/user.crt: data/user_email data/TOKEN
	$(BUILD_DIR)/data/step ca certificate --force \
		--token $(shell cat $(BUILD_DIR)/data/TOKEN) \
		--kty RSA \
		--size 2048 \
		$(shell cat $(BUILD_DIR)/data/user_email) \
		$(BUILD_DIR)/data/.step/user.crt \
		$(BUILD_DIR)/data/.step/user.key
	rm -f $(BUILD_DIR)/data/TOKEN

data/pfext01-step.ovpn: data/.step/config/defaults.json data/.step/user.crt configs-plain/files.tar
	cp -a $(BUILD_DIR)/configs-plain/pfext01-step.ovpn $(BUILD_DIR)/data/pfext01-step.ovpn.tmp
	echo "<ca>"                                      >> $(BUILD_DIR)/data/pfext01-step.ovpn.tmp
	cat $(BUILD_DIR)/data/.step/certs/root_ca.crt    >> $(BUILD_DIR)/data/pfext01-step.ovpn.tmp
	echo "</ca>"                                     >> $(BUILD_DIR)/data/pfext01-step.ovpn.tmp
	echo "<cert>"                                    >> $(BUILD_DIR)/data/pfext01-step.ovpn.tmp
	cat $(BUILD_DIR)/data/.step/user.crt             >> $(BUILD_DIR)/data/pfext01-step.ovpn.tmp
	echo "</cert>"                                   >> $(BUILD_DIR)/data/pfext01-step.ovpn.tmp
	echo "<key>"                                     >> $(BUILD_DIR)/data/pfext01-step.ovpn.tmp
	cat $(BUILD_DIR)/data/.step/user.key             >> $(BUILD_DIR)/data/pfext01-step.ovpn.tmp
	echo "</key>"                                    >> $(BUILD_DIR)/data/pfext01-step.ovpn.tmp
	mv $(BUILD_DIR)/data/pfext01-step.ovpn.tmp $(BUILD_DIR)/data/pfext01-step.ovpn

.PHONY: import-pfext01-step-openvpn
create-pfext01-step-openvpn: data/pfext01-step.ovpn ## Crea configurazione VPN in data/pfext01-step.ovpn

.PHONY: import-pfext01-step-openvpn
import-pfext01-step-openvpn: data/pfext01-step.ovpn ## Crea ed Importa configurazione VPN nel NetworkManager tramite `nmcli`
	-nmcli connection delete pfext01-step
	nmcli connection import type openvpn file $(BUILD_DIR)/data/pfext01-step.ovpn
	-echo -e "set ipv4.never-default yes\nsave\nquit" \
		| nmcli connection edit pfext01-step

.PHONY: encrypt-configs
encrypt-configs: data/step ## Cifra le configurazioni modificate
	tar cvp \
		--directory $(BUILD_DIR)/configs-plain/ \
		--file $(BUILD_DIR)/configs-plain/files.tar \
		--exclude ./files.tar \
		--exclude ./.gitignore \
		./
	$(BUILD_DIR)/data/step crypto jwe encrypt --alg PBES2-HS512+A256KW \
		< $(BUILD_DIR)/configs-plain/files.tar \
		> $(BUILD_DIR)/configs-cipher/files.tar.jwe
	rm $(BUILD_DIR)/configs-plain/files.tar

.PHONY: clean
clean:
	rm -frv $(BUILD_DIR)/data/* $(BUILD_DIR)/data/.step
