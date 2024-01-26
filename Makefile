.DELETE_ON_ERROR:

BUILD_DIR := .
STEP_VERSION := 0.25.2
STEP_BIN := $(BUILD_DIR)/data/step_$(STEP_VERSION)/bin/step
CONFIGS_CIPHER_DIR := configs-cipher
CONFIGS_PLAIN_DIR := configs-plain
VPN_NAME := confinet-pfext01-step
NETWORKMANAGER_PACKAGE := network-manager-openvpn-gnome
NSS_PACKAGE := libnss3-tools

CHECKMARK=\033[0;32m✔\033[0m
QUESTIONMARK=\033[1;41m?\033[0m

DOT_STEP_DIR=data/user
TLS_CERTS_DIR=$(DOT_STEP_DIR)/tls_user_certs
SSH_CERTS_DIR=$(DOT_STEP_DIR)/ssh_user_certs
export STEPPATH=$(BUILD_DIR)/$(DOT_STEP_DIR)

.PHONY: all
all: $(STEP_BIN) add-ssh-certificate-to-agent add-user-certificate-to-browsers add-vpn-config-to-system

data/step-$(STEP_VERSION).tgz:
	@echo -n "$(CHECKMARK) Downloading $(BUILD_DIR)/$@ ... "
	@rm -fr $(STEP_BIN)*
	@wget -q -O $(BUILD_DIR)/$@ https://github.com/smallstep/cli/releases/download/v$(STEP_VERSION)/step_linux_$(STEP_VERSION)_amd64.tar.gz
	@tar -C $(BUILD_DIR)/data -xf $(BUILD_DIR)/$@
	@echo "done."

$(STEP_BIN): data/step-$(STEP_VERSION).tgz
	@echo "$(CHECKMARK) smallstep/cli version used: $(STEP_VERSION)"

$(CONFIGS_PLAIN_DIR)/files.tar: $(CONFIGS_CIPHER_DIR)/files.tar.jwe
	@echo "$(QUESTIONMARK) $@ missing, trying to decrypt it"
	@$(STEP_BIN) crypto jwe decrypt \
		< $(BUILD_DIR)/$(CONFIGS_CIPHER_DIR)/files.tar.jwe \
		> $(BUILD_DIR)/$@
	@echo "$(CHECKMARK) Password ok"
	@tar x \
		--directory $(BUILD_DIR)/$(CONFIGS_PLAIN_DIR)/ \
		--file $(BUILD_DIR)/$@

$(DOT_STEP_DIR)/config/defaults.json: $(STEP_BIN) $(CONFIGS_PLAIN_DIR)/files.tar
	@echo -n "$(CHECKMARK) "
	@$(STEP_BIN) ca bootstrap --force \
		--ca-url $(shell cat $(BUILD_DIR)/$(CONFIGS_PLAIN_DIR)/ca-url) \
		--fingerprint  $(shell cat $(BUILD_DIR)/$(CONFIGS_PLAIN_DIR)/ca-fingerprint)

$(DOT_STEP_DIR)/user_email:
	@mkdir -p $(DOT_STEP_DIR)
	@echo -n "$(QUESTIONMARK) "
	@systemd-ask-password --echo "Identity missing, please insert your company e-mail:" > $(BUILD_DIR)/$@

$(DOT_STEP_DIR)/TLS_TOKEN: $(DOT_STEP_DIR)/config/defaults.json $(CONFIGS_PLAIN_DIR)/files.tar $(DOT_STEP_DIR)/user_email
	@mkdir -p $(TLS_CERTS_DIR)
	@echo "$(CHECKMARK) A token is required to generate the user certificate."
	@echo -n "$(CHECKMARK) "
	@$(STEP_BIN) oauth \
		--oidc \
		--bare \
		--client-id $(shell cat $(BUILD_DIR)/$(CONFIGS_PLAIN_DIR)/client-id) \
		--client-secret $(shell cat $(BUILD_DIR)/$(CONFIGS_PLAIN_DIR)/client-secret) \
		--email $(shell cat $(BUILD_DIR)/$(DOT_STEP_DIR)/user_email) \
		--prompt=select_account \
		> $(BUILD_DIR)/$@

$(TLS_CERTS_DIR)/user.crt: $(DOT_STEP_DIR)/user_email $(DOT_STEP_DIR)/TLS_TOKEN
	@$(STEP_BIN) ca certificate --force \
		--token $(shell cat $(BUILD_DIR)/$(DOT_STEP_DIR)/TLS_TOKEN) \
		$(shell cat $(BUILD_DIR)/$(DOT_STEP_DIR)/user_email) \
		$(BUILD_DIR)/$@ \
		$(BUILD_DIR)/$(patsubst %.crt,%.key,$@)
	@$(STEP_BIN) certificate inspect --short $(BUILD_DIR)/$@ \
		| tail -n1 \
		| sed 's/\s\+to:\s\+//' \
		| xargs date +%s -d \
		> $(BUILD_DIR)/$@.expiresAt
	@openssl pkcs12 \
		-passout pass: \
		-inkey $(BUILD_DIR)/$(TLS_CERTS_DIR)/user.key \
		-in $(BUILD_DIR)/$@ \
		-export \
		-out $(BUILD_DIR)/$@.p12
	@echo "$(CHECKMARK) PKCS #12: $(BUILD_DIR)/$@.p12"

$(DOT_STEP_DIR)/SSH_TOKEN: $(DOT_STEP_DIR)/user_email $(TLS_CERTS_DIR)/user.crt
	@mkdir -p $(SSH_CERTS_DIR)
	@echo "$(CHECKMARK) A token is required to generate the ssh certificate."
	@$(STEP_BIN) ca token \
		$(shell cat $(BUILD_DIR)/$(DOT_STEP_DIR)/user_email) \
		--ssh \
		--provisioner "x5c-for-ssh" \
		--x5c-cert $(BUILD_DIR)/$(TLS_CERTS_DIR)/user.crt \
		--x5c-key $(BUILD_DIR)/$(TLS_CERTS_DIR)/user.key \
		> $(BUILD_DIR)/$@

$(SSH_CERTS_DIR)/ssh_user_key-cert.pub: $(DOT_STEP_DIR)/user_email $(TLS_CERTS_DIR)/user.crt $(DOT_STEP_DIR)/SSH_TOKEN
	@rm -f $(BUILD_DIR)/$(SSH_CERTS_DIR)/ssh_user_key*
	@ssh-keygen \
		-t ed25519 \
		-N '' \
		-f $(BUILD_DIR)/$(SSH_CERTS_DIR)/ssh_user_key \
		> /dev/null
	@echo "$(CHECKMARK) SSH private key: $(BUILD_DIR)/$(SSH_CERTS_DIR)/ssh_user_key"
	@echo "$(CHECKMARK) SSH public key:  $(BUILD_DIR)/$(SSH_CERTS_DIR)/ssh_user_key.pub"
	@$(STEP_BIN) ssh certificate \
		$(shell cat $(BUILD_DIR)/$(DOT_STEP_DIR)/user_email) \
		$(BUILD_DIR)/$(SSH_CERTS_DIR)/ssh_user_key.pub \
		--token "$(shell cat $(BUILD_DIR)/$(DOT_STEP_DIR)/SSH_TOKEN)" \
		--sign
	@rm $(BUILD_DIR)/$(DOT_STEP_DIR)/SSH_TOKEN

.PHONY: check-expiration
check-expiration:
	@if [ $(shell date +%s) -ge $(shell cat $(BUILD_DIR)/$(TLS_CERTS_DIR)/user.crt.expiresAt 2> /dev/null || echo 0) ]; then \
		ssh-add -d $(BUILD_DIR)/$(SSH_CERTS_DIR)/ssh_user_key > /dev/null || true; \
		rm -f $(BUILD_DIR)/$(TLS_CERTS_DIR)/* $(BUILD_DIR)/data/TOKEN; \
		echo "$(CHECKMARK) User certificates expired: removed"; \
	else \
		echo "$(CHECKMARK) User certificates still valid"; \
	fi;

.PHONY: create-ssh-certificate
create-ssh-certificate: check-expiration $(SSH_CERTS_DIR)/ssh_user_key-cert.pub

.PHONY: add-ssh-certificate-to-agent
add-ssh-certificate-to-agent: check-expiration $(SSH_CERTS_DIR)/ssh_user_key-cert.pub
	@ssh-add $(BUILD_DIR)/$(SSH_CERTS_DIR)/ssh_user_key

.PHONY: create-user-certificate
create-user-certificate: check-expiration $(TLS_CERTS_DIR)/user.crt

.PHONY: check-nss
check-nss:
	@if [ -z "$(shell dpkg -l | grep $(NSS_PACKAGE) 2> /dev/null)" ]; then \
		echo "$(QUESTIONMARK) Package $(NSS_PACKAGE) is required to add certificates to browsers but is missing from your system"; \
		echo -n "$(QUESTIONMARK) Do you want to run \`sudo apt install $(NSS_PACKAGE)\` to install it? [y/N] " && read ans && [ $${ans:-N} != y ] && echo "Aborted" && exit 1; \
		sudo apt install $(NSS_PACKAGE); \
	fi;
	@echo "$(CHECKMARK) Package \`$(NSS_PACKAGE)\` present in the system"; \

.PHONY: add-user-certificate-to-browsers
add-user-certificate-to-browsers: check-nss check-expiration $(TLS_CERTS_DIR)/user.crt
	@$(foreach profile,$(shell ls $(HOME)/.mozilla/firefox/*/cert9.db $(HOME)/snap/firefox/common/.mozilla/firefox/*/cert9.db $(HOME)/.pki/nssdb/cert9.db 2> /dev/null), \
		certutil -D -d $(shell dirname "$(profile)")/ -n $(shell cat $(BUILD_DIR)/$(DOT_STEP_DIR)/user_email) > /dev/null; \
		pk12util -i $(BUILD_DIR)/$(TLS_CERTS_DIR)/user.crt.p12 -d $(shell dirname "$(profile)")/ -W ""  > /dev/null; \
		echo "$(CHECKMARK) User certificate added to: $(profile)"; \
	)

$(DOT_STEP_DIR)/$(VPN_NAME).ovpn: $(DOT_STEP_DIR)/config/defaults.json check-expiration $(TLS_CERTS_DIR)/user.crt $(CONFIGS_PLAIN_DIR)/files.tar
	@cp -a $(BUILD_DIR)/$(CONFIGS_PLAIN_DIR)/pfext01-step.ovpn  $(BUILD_DIR)/$@.tmp
	@echo "<ca>"                                      	>> $(BUILD_DIR)/$@.tmp
	@cat $(BUILD_DIR)/$(DOT_STEP_DIR)/certs/root_ca.crt	>> $(BUILD_DIR)/$@.tmp
	@echo "</ca>"                                     	>> $(BUILD_DIR)/$@.tmp
	@echo "<cert>"                                    	>> $(BUILD_DIR)/$@.tmp
	@cat $(BUILD_DIR)/$(TLS_CERTS_DIR)/user.crt      	>> $(BUILD_DIR)/$@.tmp
	@echo "</cert>"                                   	>> $(BUILD_DIR)/$@.tmp
	@echo "<key>"                                     	>> $(BUILD_DIR)/$@.tmp
	@cat $(BUILD_DIR)/$(TLS_CERTS_DIR)/user.key      	>> $(BUILD_DIR)/$@.tmp
	@echo "</key>"                                    	>> $(BUILD_DIR)/$@.tmp
	@mv $(BUILD_DIR)/$@.tmp $(BUILD_DIR)/$@
	@echo "$(CHECKMARK) OpenVPN config: $(BUILD_DIR)/$@"

.PHONY: check-networkmanager
check-networkmanager:
	@if [ -z "$(shell dpkg -l | grep $(NETWORKMANAGER_PACKAGE) 2> /dev/null)" ]; then \
		echo "$(QUESTIONMARK) Package $(NETWORKMANAGER_PACKAGE) is required to add OpenVPN config to system but is missing from your system"; \
		echo -n "$(QUESTIONMARK) Do you want to run \`sudo apt install $(NETWORKMANAGER_PACKAGE)\` to install it? [y/N] " && read ans && [ $${ans:-N} != y ] && echo "Aborted" && exit 1; \
		sudo apt install $(NETWORKMANAGER_PACKAGE); \
	fi;
	@echo "$(CHECKMARK) Package \`$(NETWORKMANAGER_PACKAGE)\` present in the system"; \

.PHONY: create-vpn-config
create-vpn-config: $(DOT_STEP_DIR)/$(VPN_NAME).ovpn

.PHONY: add-vpn-config-to-system
add-vpn-config-to-system: $(DOT_STEP_DIR)/$(VPN_NAME).ovpn check-networkmanager
	@nmcli connection delete $(VPN_NAME) > /dev/null 2> /dev/null || true
	@echo -n "$(CHECKMARK) "
	@nmcli connection import type openvpn file $(BUILD_DIR)/$(DOT_STEP_DIR)/$(VPN_NAME).ovpn
	@-echo "set ipv4.never-default yes\nsave\nquit" \
		| nmcli connection edit $(VPN_NAME) > /dev/null
	@echo "$(CHECKMARK) Type \`nmcli connection up $(VPN_NAME)\` to start the VPN from cli"

.PHONY: encrypt-configs
encrypt-configs: data/step-$(STEP_VERSION).tgz
	tar cvp \
		--directory $(BUILD_DIR)/$(CONFIGS_PLAIN_DIR)/ \
		--file $(BUILD_DIR)/$(CONFIGS_PLAIN_DIR)/files.tar \
		--exclude ./files.tar \
		--exclude ./.gitignore \
		./
	$(STEP_BIN) crypto jwe encrypt --alg PBES2-HS512+A256KW \
		< $(BUILD_DIR)/$(CONFIGS_PLAIN_DIR)/files.tar \
		> $(BUILD_DIR)/$(CONFIGS_CIPHER_DIR)/files.tar.jwe
	rm $(BUILD_DIR)/$(CONFIGS_PLAIN_DIR)/files.tar

.PHONY: clean
clean:
	rm -fr $(BUILD_DIR)/data/*
