.DELETE_ON_ERROR:

BUILD_DIR := .
STEP_VERSION := 0.21.0
STEP_BIN := $(BUILD_DIR)/data/step_$(STEP_VERSION)/bin/step
CONFIGS_CIPHER_DIR := configs-cipher
CONFIGS_PLAIN_DIR := configs-plain
VPN_NAME := confinet-pfext01-step
NETWORKMANAGER_PACKAGE := network-manager-openvpn-gnome
NSS_PACKAGE := libnss3-tools

export STEPPATH=$(BUILD_DIR)/data/.step

define obtain_token
	@echo "A token is required to generate the next certificate."
	@$(STEP_BIN) oauth \
		--oidc \
		--bare \
		--client-id $(shell cat $(BUILD_DIR)/$(CONFIGS_PLAIN_DIR)/client-id) \
		--client-secret $(shell cat $(BUILD_DIR)/$(CONFIGS_PLAIN_DIR)/client-secret) \
		--email $(shell cat $(BUILD_DIR)/data/user_email) \
		--prompt=select_account \
		> $(BUILD_DIR)/$@
endef

.PHONY: all
all: $(STEP_BIN) add-user-certificate-to-browsers add-ssh-certificate-to-agent import-pfext01-step-openvpn

data/step-$(STEP_VERSION).tgz:
	@echo -n "Downloading $(BUILD_DIR)/$@ ... "
	@rm -fr $(STEP_BIN)*
	@wget -q -O $(BUILD_DIR)/$@ https://github.com/smallstep/cli/releases/download/v$(STEP_VERSION)/step_linux_$(STEP_VERSION)_amd64.tar.gz
	@tar -C $(BUILD_DIR)/data -xf $(BUILD_DIR)/$@
	@echo "done."

$(STEP_BIN): data/step-$(STEP_VERSION).tgz

$(CONFIGS_PLAIN_DIR)/files.tar: $(CONFIGS_CIPHER_DIR)/files.tar.jwe
	$(STEP_BIN) crypto jwe decrypt \
		< $(BUILD_DIR)/$(CONFIGS_CIPHER_DIR)/files.tar.jwe \
		> $(BUILD_DIR)/$@
	tar xv \
		--directory $(BUILD_DIR)/$(CONFIGS_PLAIN_DIR)/ \
		--file $(BUILD_DIR)/$@

data/.step/config/defaults.json: $(STEP_BIN) $(CONFIGS_PLAIN_DIR)/files.tar
	@$(STEP_BIN) ca bootstrap --force \
		--ca-url $(shell cat $(BUILD_DIR)/$(CONFIGS_PLAIN_DIR)/ca-url) \
		--fingerprint  $(shell cat $(BUILD_DIR)/$(CONFIGS_PLAIN_DIR)/ca-fingerprint)

data/user_email:
	@systemd-ask-password --echo "Insert your company e-mail:" > $(BUILD_DIR)/$@

data/TOKEN_crt: data/.step/config/defaults.json $(CONFIGS_PLAIN_DIR)/files.tar data/user_email
	$(obtain_token)

data/TOKEN_ssh_crt: data/.step/config/defaults.json $(CONFIGS_PLAIN_DIR)/files.tar data/user_email
	$(obtain_token)

data/.step/user.crt: data/user_email data/TOKEN_crt
	@$(STEP_BIN) ca certificate --force \
		--token $(shell cat $(BUILD_DIR)/data/TOKEN_crt) \
		--kty RSA \
		--size 2048 \
		$(shell cat $(BUILD_DIR)/data/user_email) \
		$(BUILD_DIR)/$@ \
		$(BUILD_DIR)/$(patsubst %.crt,%.key,$@)
	@$(STEP_BIN) certificate inspect --short $(BUILD_DIR)/$@ \
		| tail -n1 \
		| sed 's/\s\+to:\s\+//' \
		| xargs date +%s -d \
		> $(BUILD_DIR)/$@.expiresAt
	@openssl pkcs12 \
		-nodes \
		-passout pass: \
		-inkey $(BUILD_DIR)/data/.step/user.key \
		-in $(BUILD_DIR)/$@ \
		-export \
		-out $(BUILD_DIR)/$@.p12
	@echo "✔ PKCS #12: $(BUILD_DIR)/$@.p12"

data/.step/ssh_user_key-cert.pub: data/user_email data/TOKEN_ssh_crt
	@rm -f $(BUILD_DIR)/data/.step/ssh_user_key*
	@ssh-keygen \
		-t ed25519 \
		-N '' \
		-f $(BUILD_DIR)/data/.step/ssh_user_key \
		> /dev/null
	@echo "✔ SSH private key: $(BUILD_DIR)/data/.step/ssh_user_key"
	@echo "✔ SSH public key:  $(BUILD_DIR)/data/.step/ssh_user_key.pub"
	@$(STEP_BIN) ssh certificate \
		$(shell cat $(BUILD_DIR)/data/user_email) \
		$(BUILD_DIR)/data/.step/ssh_user_key.pub \
		--token $(shell cat $(BUILD_DIR)/data/TOKEN_ssh_crt) \
		--sign
	@$(STEP_BIN) ssh inspect $(BUILD_DIR)/$@ \
		| grep Valid: \
		| sed 's/.\+to //' \
		| xargs date +%s -d \
		> $(BUILD_DIR)/$@.expiresAt

.PHONY: check-expiration
check-expiration:
	@if [ $(shell date +%s) -ge $(shell cat $(BUILD_DIR)/data/.step/user.crt.expiresAt 2> /dev/null || echo 0) ]; then \
		rm -f $(BUILD_DIR)/data/.step/user.* $(BUILD_DIR)/data/TOKEN_crt; \
		echo "User certificate expired: removed"; \
	fi;
	@if [ $(shell date +%s) -ge $(shell cat $(BUILD_DIR)/data/.step/ssh_user_key-cert.pub.expiresAt 2> /dev/null  || echo 0) ]; then \
		ssh-add -d $(BUILD_DIR)/data/.step/ssh_user_key > /dev/null || true; \
		rm -f $(BUILD_DIR)/data/.step/ssh_user_key* $(BUILD_DIR)/data/TOKEN_ssh_crt; \
		echo "User SSH certificate expired: removed"; \
	fi;

data/$(VPN_NAME).ovpn: data/.step/config/defaults.json check-expiration data/.step/user.crt $(CONFIGS_PLAIN_DIR)/files.tar
	@cp -a $(BUILD_DIR)/$(CONFIGS_PLAIN_DIR)/pfext01-step.ovpn  $(BUILD_DIR)/$@.tmp
	@echo "<ca>"                                      >> $(BUILD_DIR)/$@.tmp
	@cat $(BUILD_DIR)/data/.step/certs/root_ca.crt    >> $(BUILD_DIR)/$@.tmp
	@echo "</ca>"                                     >> $(BUILD_DIR)/$@.tmp
	@echo "<cert>"                                    >> $(BUILD_DIR)/$@.tmp
	@cat $(BUILD_DIR)/data/.step/user.crt             >> $(BUILD_DIR)/$@.tmp
	@echo "</cert>"                                   >> $(BUILD_DIR)/$@.tmp
	@echo "<key>"                                     >> $(BUILD_DIR)/$@.tmp
	@cat $(BUILD_DIR)/data/.step/user.key             >> $(BUILD_DIR)/$@.tmp
	@echo "</key>"                                    >> $(BUILD_DIR)/$@.tmp
	@mv $(BUILD_DIR)/$@.tmp $(BUILD_DIR)/$@

.PHONY: check-networkmanager
check-networkmanager:
	@dpkg -l | grep $(NETWORKMANAGER_PACKAGE) > /dev/null || \
		echo "È richiesta l'installazione del pacchetto $(NETWORKMANAGER_PACKAGE), esegui:\n$$ sudo apt install $(NETWORKMANAGER_PACKAGE)"

.PHONY: import-pfext01-step-openvpn
import-pfext01-step-openvpn: data/$(VPN_NAME).ovpn check-networkmanager
	@nmcli connection delete $(VPN_NAME) > /dev/null 2> /dev/null || true
	@nmcli connection import type openvpn file $(BUILD_DIR)/data/$(VPN_NAME).ovpn
	@-echo "set ipv4.never-default yes\nsave\nquit" \
		| nmcli connection edit $(VPN_NAME) > /dev/null

.PHONY: check-nss
check-nss:
	@dpkg -l | grep $(NSS_PACKAGE) > /dev/null || \
		echo "Package $(NSS_PACKAGE) is required to add certs to browsers, run this command to install it:\n$$ sudo apt install $(NSS_PACKAGE)"

.PHONY: add-user-certificate-to-browsers
add-user-certificate-to-browsers: check-nss check-expiration data/.step/user.crt
	@$(foreach profile,$(shell ls $(HOME)/.mozilla/firefox/*/cert9.db $(HOME)/snap/firefox/common/.mozilla/firefox/*/cert9.db $(HOME)/.pki/nssdb/cert9.db), \
		certutil -D -d $(shell dirname "$(profile)")/ -n $(shell cat $(BUILD_DIR)/data/user_email) > /dev/null; \
		pk12util -i $(BUILD_DIR)/data/.step/user.crt.p12 -d $(shell dirname "$(profile)")/ -W ""  > /dev/null; \
		echo "User certificate added to: $(profile)"; \
	)

.PHONY: import-ssh-certificate-to-agent
add-ssh-certificate-to-agent: check-expiration data/.step/ssh_user_key-cert.pub
	@ssh-add $(BUILD_DIR)/data/.step/ssh_user_key

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
	@rm -fr $(BUILD_DIR)/data/* $(BUILD_DIR)/data/.step
