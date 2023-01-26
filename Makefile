SHELL = /bin/bash
.SHELLFLAGS = -o pipefail -c

all: help

.PHONY: help  ## Print this help
help: about
	@printf '\n\033[1;36m%-12s\033[0m %s\n────────────────────────\n' "Command" "Description"
	@awk 'BEGIN {FS = " *## |: "}; /^.PHONY: /{printf "\033[1;36m%-15s\033[0m %s\n", $$2, $$3}' $(MAKEFILE_LIST)

.PHONY: about  ## Describe this tool
NAME = 'fuzzy_parser'
TITLE = 'Python Parser for Abbreviated Dates'
about:
	@echo $(NAME) -- $(TITLE)

#
# Superuser rules
#
.PHONY: utilities  ## Install utilities required for the tool (Run with sudo)
DISTRIBUTION_CODENAME := $(shell awk -F'=' '/UBUNTU_CODENAME/{print $$2}' /etc/os-release)
SUPPORTED_DISTRIBUTIONS := focal jammy
ifeq ($(filter $(DISTRIBUTION_CODENAME),$(SUPPORTED_DISTRIBUTIONS)),)
    $(warning Terminating on detection of unsupported Ubuntu distribution: $(DISTRIBUTION_CODENAME). \
    Supported distibutions are: $(SUPPORTED_DISTRIBUTIONS))
endif
utilities: packages /usr/bin/swipl

.PHONY: packages  ## Install packages required for the tool (Run with sudo)
packages:
	@sudo apt-get update
	@apt-get -qqy install git bumpversion build-essential software-properties-common jq python3-venv python3-pip

PROLOG_LIST_FILE = /etc/apt/sources.list.d/swi-prolog-ubuntu-stable-$(DISTRIBUTION_CODENAME).list
/usr/bin/swipl: $(PROLOG_LIST_FILE)
	@apt-get -qqy install swi-prolog-nox
	@touch $@
$(PROLOG_LIST_FILE):
	@apt-add-repository -y ppa:swi-prolog/stable
	@touch $@

ARCH=$(shell dpkg --print-architecture)
GH_KEYRING = /usr/share/keyrings/githubcli-archive-keyring.gpg
GH_LIST = "deb [arch=$(ARCH) signed-by=$(GH_KEYRING)] https://cli.github.com/packages stable main"
GH_LIST_FILE = /etc/apt/sources.list.d/github-cli.list

/usr/bin/gh: $(GH_LIST_FILE)
	@apt-get install $(notdir $@) -y
	@touch $@

$(GH_LIST_FILE): $(GH_KEYRING)
	@echo $(GH_LIST) | sudo tee $(GH_LIST_FILE) > /dev/null
	@sudo apt-get update
	@touch $@

$(GH_KEYRING):
	@curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | sudo dd of=$(GH_KEYRING)
	@touch $@

/usr/bin/%: # Install packages from default repo
	@apt-get -qqy install $(notdir $@)
	@touch $@

.PHONY: clean-utilities ## Test utilities installation with sudo make clean-utilities utilities && make test
clean-utilities:
	@apt-get --purge -qqy autoremove swi-prolog-nox bumpversion python3-venv python3-pip
	@add-apt-repository --remove -y ppa:swi-prolog/stable
	@rm -f /etc/apt/sources.list.d/swi-prolog-ubuntu-stable-$(DISTRIBUTION_CODENAME).list
	@apt-get -y autoremove

#
# Unprivileged user rules
#
.PHONY: synchronize ## Synchronize the local repository: Switch to the main branch, fetch changes & delete merged branches
synchronize: /usr/bin/git
	@git checkout master && git pull && git branch --merged | egrep -v "(^\*|master)" | xargs -r git branch -d || exit 0

.PHONY: test ## Run the test suite
VENV = venv
PYTHON_PATH = $(VENV)/bin
PYTHON = $(PYTHON_PATH)/python3
test: $(PYTHON_PATH)/pytest parser
	@$(PYTHON) -m pytest -p no:cacheprovider

$(PYTHON_PATH)/%: $(VENV)/bin/activate # Install packages from default repo
	@$(PYTHON) -m pip install $(notdir $@)

$(VENV)/bin/activate: requirements.txt
	@test -d $(VENV) || python3 -m venv $(VENV)
	@$(PYTHON) -m pip install --upgrade pip
	@$(PYTHON) -m pip install --use-pep517 -r requirements.txt
	@touch $@

.PHONY: parser ## Install the latest parser release. Override parser version with make VERSION=v0.0.? parser
PACK_PATH = ${HOME}/.local/share/swi-prolog/pack
parser: $(PACK_PATH)/abbreviated_dates
$(PACK_PATH)/abbreviated_dates: $(PACK_PATH)/tap  $(PACK_PATH)/date_time
	@: $${VERSION:=$$(curl --silent 'https://api.github.com/repos/crgz/abbreviated_dates/releases/latest'|jq -r .tag_name)} ;\
	REMOTE=https://github.com/crgz/abbreviated_dates/archive/$$VERSION.zip ;\
	swipl -qg "pack_remove(abbreviated_dates),pack_install('$$REMOTE',[interactive(false)]),halt(0)" -t 'halt(1)'
	@touch $@

$(PACK_PATH)/%:
	@swipl -qg "pack_install('$(notdir $@)',[interactive(false)]),halt"
	@touch $@

.PHONY: bump ## Increase the version number
bump: export GH_TOKEN ?= $(shell secret-tool lookup user ${USER} domain github.com) # Overridable
bump: /usr/bin/bumpversion committer
	@git push -d origin release || true
	@git checkout -b release
	@bumpversion --allow-dirty --list patch
	@git push origin release
	@gh pr create -B main -H release --fill
	@gh pr merge -m --auto --delete-branch

.PHONY: release ## Release a new version (Requires unprotected main branch or special token to be used from Github Actions)
TOKEN ?= $(shell secret-tool lookup user ${USER} domain pypi.org ) # Overridable
release: build
	@$(PYTHON) -m twine upload --skip-existing -u "__token__" -p $(TOKEN) dist/*

.PHONY: build ## Build and check distribution packages
build: $(PYTHON_PATH)/build $(PYTHON_PATH)/twine
	@$(PYTHON) -m build --sdist --wheel
	@$(PYTHON) -m twine check dist/*

.PHONY: clean ## Remove debris from build target
clean:  /usr/bin/swipl uninstall
	@rm -rfd fuzzy_parser.egg-info/ dist/ .pytest_cache/ __pycache__
	@rm -rfd $(VENV)
	@swipl -g "(member(P,[abbreviated_dates,date_time,tap]),pack_property(P,library(P)),pack_remove(P),fail);true,halt"

.PHONY: uninstall   ## Uninstall the library
uninstall: $(PYTHON_PATH)/$(NAME)
	@$(PIP) uninstall -y $(NAME)

.PHONY: store-token ## Store the Github token
store-token:
	@secret-tool store --label='github.com/crgz' user ${USER} domain github.com

.PHONY: committer ## config committer credentials
committer:
	@git config --global user.email "conrado.rgz@gmail.com"
	@git config --global user.name "Conrado Rodriguez"
	@git config pull.ff only
