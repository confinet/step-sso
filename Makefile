.DELETE_ON_ERROR:

BUILD_DIR := .
STEP_VERSION := 0.16.1
CONFIGS_CIPHER_DIR := configs-cipher
CONFIGS_PLAIN_DIR := configs-plain
VPN_NAME := confinet-pfext01-step

# xdg-open for "step oauth" command has a bug in Ubuntu 16.04
# which sends to the browser a wrong URL
XDGOPEN_MIN := 1.1.2
XDGOPEN_CUR := $(shell xdg-open --version | cut -d' ' -f2)
XDGOPEN_FLAG := $(shell if [  "$(XDGOPEN_CUR)" = "$(shell printf '%s\n%s' "$(XDGOPEN_CUR)" "$(XDGOPEN_MIN)" | sort -V | head -n1)" ]; then echo --console; fi;)

NETWORKMANAGER_PACKAGE := network-manager-openvpn-gnome
NSS_PACKAGE := libnss3-tools

export STEPPATH=$(BUILD_DIR)/data/.step

.PHONY: help
help:
	@echo "Comandi disponibili:"
	@grep -E '^[a-zA-Z0-9_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[32m%-30s\033[0m %s\n", $$1, $$2}'

data/step-$(STEP_VERSION).tgz:
	rm -frv $(BUILD_DIR)/data/step*
	# Waiting for https://github.com/smallstep/cli/pull/413
	wget -O $(BUILD_DIR)/$@ https://github.com/smallstep/cli/releases/download/v$(STEP_VERSION)/step_linux_$(STEP_VERSION)_amd64.tar.gz
	tar -C $(BUILD_DIR)/data -xf $(BUILD_DIR)/$@
	ln -s step_$(STEP_VERSION)/bin/step $(BUILD_DIR)/data/step

data/step: data/step-$(STEP_VERSION).tgz

$(CONFIGS_PLAIN_DIR)/files.tar: $(CONFIGS_CIPHER_DIR)/files.tar.jwe
	$(BUILD_DIR)/data/step crypto jwe decrypt \
		< $(BUILD_DIR)/$(CONFIGS_CIPHER_DIR)/files.tar.jwe \
		> $(BUILD_DIR)/$@
	tar xv \
		--directory $(BUILD_DIR)/$(CONFIGS_PLAIN_DIR)/ \
		--file $(BUILD_DIR)/$@

data/.step/config/defaults.json: data/step-$(STEP_VERSION).tgz $(CONFIGS_PLAIN_DIR)/files.tar
	$(BUILD_DIR)/data/step ca bootstrap --force \
		--ca-url $(shell cat $(BUILD_DIR)/$(CONFIGS_PLAIN_DIR)/ca-url) \
		--fingerprint  $(shell cat $(BUILD_DIR)/$(CONFIGS_PLAIN_DIR)/ca-fingerprint)

data/user_email:
	systemd-ask-password --echo "Inserisci la tua email Confinet:" > $(BUILD_DIR)/$@

data/TOKEN: data/.step/config/defaults.json $(CONFIGS_PLAIN_DIR)/files.tar data/user_email
	$(BUILD_DIR)/data/step oauth \
		--oidc \
		--bare \
		--client-id $(shell cat $(BUILD_DIR)/$(CONFIGS_PLAIN_DIR)/client-id) \
		--client-secret $(shell cat $(BUILD_DIR)/$(CONFIGS_PLAIN_DIR)/client-secret) \
		--email $(shell cat $(BUILD_DIR)/data/user_email) \
		--prompt=select_account $(XDGOPEN_FLAG) \
		> $(BUILD_DIR)/$@

data/.step/user.crt: data/user_email data/TOKEN
	$(BUILD_DIR)/data/step ca certificate --force \
		--token $(shell cat $(BUILD_DIR)/data/TOKEN) \
		--kty RSA \
		--size 2048 \
		$(shell cat $(BUILD_DIR)/data/user_email) \
		$(BUILD_DIR)/$@ \
		$(BUILD_DIR)/$(patsubst %.crt,%.key,$@)
	$(BUILD_DIR)/data/step certificate inspect --short $(BUILD_DIR)/$@ \
		| tail -n1 \
		| sed 's/\s\+to:\s\+//' \
		| xargs date +%s -d \
		> $(BUILD_DIR)/$@.expiresAt
	openssl pkcs12 -nodes -passout pass: -inkey data/.step/user.key -in data/.step/user.crt -export -out data/.step/user.p12

.PHONY: check-crt-expiration
check-crt-expiration:
	if [ $(shell date +%s) -ge $(shell cat $(BUILD_DIR)/data/.step/user.crt.expiresAt || echo 0) ]; then \
		rm -f $(BUILD_DIR)/data/.step/user.crt $(BUILD_DIR)/data/TOKEN; \
	fi;

data/$(VPN_NAME).ovpn: data/.step/config/defaults.json check-crt-expiration data/.step/user.crt $(CONFIGS_PLAIN_DIR)/files.tar
	cp -a $(BUILD_DIR)/$(CONFIGS_PLAIN_DIR)/pfext01-step.ovpn  $(BUILD_DIR)/$@.tmp
	echo "<ca>"                                      >> $(BUILD_DIR)/$@.tmp
	cat $(BUILD_DIR)/data/.step/certs/root_ca.crt    >> $(BUILD_DIR)/$@.tmp
	echo "</ca>"                                     >> $(BUILD_DIR)/$@.tmp
	echo "<cert>"                                    >> $(BUILD_DIR)/$@.tmp
	cat $(BUILD_DIR)/data/.step/user.crt             >> $(BUILD_DIR)/$@.tmp
	echo "</cert>"                                   >> $(BUILD_DIR)/$@.tmp
	echo "<key>"                                     >> $(BUILD_DIR)/$@.tmp
	cat $(BUILD_DIR)/data/.step/user.key             >> $(BUILD_DIR)/$@.tmp
	echo "</key>"                                    >> $(BUILD_DIR)/$@.tmp
	mv $(BUILD_DIR)/$@.tmp $(BUILD_DIR)/$@

.PHONY: create-pfext01-step-openvpn
create-pfext01-step-openvpn: data/$(VPN_NAME).ovpn ## Crea configurazione VPN in ./data/

.PHONY: check-networkmanager
check-networkmanager:
	@dpkg -l | grep $(NETWORKMANAGER_PACKAGE) || \
		echo "È richiesta l'installazione del pacchetto $(NETWORKMANAGER_PACKAGE), esegui:\n$$ sudo apt install $(NETWORKMANAGER_PACKAGE)"

.PHONY: import-pfext01-step-openvpn
import-pfext01-step-openvpn: data/$(VPN_NAME).ovpn check-networkmanager ## Crea ed Importa configurazione VPN nel NetworkManager tramite `nmcli`
	-nmcli connection delete $(VPN_NAME)
	nmcli connection import type openvpn file $(BUILD_DIR)/data/$(VPN_NAME).ovpn
	-echo "set ipv4.never-default yes\nsave\nquit" \
		| nmcli connection edit $(VPN_NAME)

.PHONY: check-nss
check-nss:
	@dpkg -l | grep $(NSS_PACKAGE) || \
		echo "È richiesta l'installazione del pacchetto $(NSS_PACKAGE), esegui:\n$$ sudo apt install $(NSS_PACKAGE)"

.PHONY: import-p12-into-firefox
import-p12-into-firefox: check-nss check-crt-expiration data/.step/user.crt $(CONFIGS_PLAIN_DIR)/files.tar
	$(foreach profile,$(shell ls $(HOME)/.mozilla/firefox/*/cert9.db $(HOME)/snap/firefox/common/.mozilla/firefox/*/cert9.db), \
		certutil -D -d $(shell dirname "$(profile)")/ -n $(shell cat $(BUILD_DIR)/data/user_email); \
		pk12util -i data/.step/user.p12 -d $(shell dirname "$(profile)")/ -W ""; \
	)
	
.PHONY: encrypt-configs
encrypt-configs: data/step-$(STEP_VERSION).tgz ## Cifra le configurazioni modificate
	tar cvp \
		--directory $(BUILD_DIR)/$(CONFIGS_PLAIN_DIR)/ \
		--file $(BUILD_DIR)/$(CONFIGS_PLAIN_DIR)/files.tar \
		--exclude ./files.tar \
		--exclude ./.gitignore \
		./
	$(BUILD_DIR)/data/step crypto jwe encrypt --alg PBES2-HS512+A256KW \
		< $(BUILD_DIR)/$(CONFIGS_PLAIN_DIR)/files.tar \
		> $(BUILD_DIR)/$(CONFIGS_CIPHER_DIR)/files.tar.jwe
	rm $(BUILD_DIR)/$(CONFIGS_PLAIN_DIR)/files.tar

.PHONY: clean
clean:
	rm -frv $(BUILD_DIR)/data/* $(BUILD_DIR)/data/.step
