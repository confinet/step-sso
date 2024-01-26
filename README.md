# Confinet STEP SSO

This repo allows `@confinet.it` users to acquire X.509 and SSH certificates
for daily work, and configure system to use them.

## Requirements

Tested on Ubuntu >= 22.04, may work in any Debian/Ubuntu based distro

## Installation

```console
git clone https://github.com/confinet/step-sso.git ~/repos/confinet-step-sso
```

## Usage

### Create certs only (no system modifications)

| Command | Generated files |
| --- | --- |
| `make create-ssh-certificate` | `./data/user/ssh_user_certs/ssh_user_key` <br> `./data/user/ssh_user_certs/ssh_user_key.pub` <br> `./data/user/ssh_user_certs/ssh_user_key-cert.pub` |
| `make create-user-certificate` | `./data/user/tls_user_certs/user.crt` <br> `./data/user/tls_user_certs/user.key` <br> `./data/user/tls_user_certs/user.crt.p12` |
| `make create-vpn-config` | `./data/user/confinet-pfext01-step.ovpn` |

### Import certs in system

| Command | System edits |
| --- | --- |
| `make add-ssh-certificate-to-agent` | Adds SSH key + cert in default ssh-agent, see `ssh-add -L` result |
| `make add-user-certificate-to-browsers` | Adds PKCS#12 cert to Firefox and Chrome profiles found <br> *Warning*: `libnss3-tools` package required |
| `make add-vpn-config-to-system` | Adds OpenVPN config to system connections <br> *Warning*: `network-manager-openvpn-gnome` package required |

### Everything

`make`

## Auto-select cert on Firefox

Open `about:config` and set:

```
security.default_personal_cert                    => Select Automatically
security.remember_cert_checkbox_default_setting   => false
```
