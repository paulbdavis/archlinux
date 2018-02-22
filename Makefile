include .print.mk

MAKEPKGFLAGS =
MAKEPKG = makepkg $(MAKEPKGFLAGS)
PKG_SUFFIX := pkg.tar.xz
SIG_SUFFIX := $(PKG_SUFFIX).sig
PKG_DIR := pkg

get_pkg_name = $(shell cd $(PKG_DIR)/$(1) && makepkg --packagelist)
get_pkg_sources = $(addprefix $(dir $(1)),$(shell cd $(dir $(1)) && makepkg --printsrcinfo | grep 'source = ' | awk '{print $$3}' | tr '\n' ' '))
sign = gpg --output $(1) --detach-sign $(2)

PKG_DIRS := $(wildcard $(PKG_DIR)/*)
PKGS := $(foreach pkgname,$(notdir $(PKG_DIRS)),$(PKG_DIR)/$(pkgname)/$(call get_pkg_name,$(pkgname)).$(PKG_SUFFIX))
SIGS := $(foreach pkgname,$(notdir $(PKG_DIRS)),$(PKG_DIR)/$(pkgname)/$(call get_pkg_name,$(pkgname)).$(SIG_SUFFIX))

REPO_NAME=dangersalad
REPO_DIR := repo
REMOTE_REPO_DIR := repo-remote
DB_FILE := $(REPO_DIR)/$(REPO_NAME).db.tar.gz
FILES_FILE := $(REPO_DIR)/$(REPO_NAME).files
DB_SIG := $(REPO_DIR)/$(REPO_NAME).db.sig
FILES_SIG := $(REPO_DIR)/$(REPO_NAME).files.sig
REMOTE_DB_FILE := $(REMOTE_REPO_DIR)/$(REPO_NAME).db
REMOTE_FILES_FILE := $(REMOTE_REPO_DIR)/$(REPO_NAME).files
REMOTE_DB_SIG := $(REMOTE_REPO_DIR)/$(REPO_NAME).db.sig
REMOTE_FILES_SIG := $(REMOTE_REPO_DIR)/$(REPO_NAME).files.sig

space :=
space +=

all: $(PKGS) $(SIGS)

sync: $(SIGS)
	$(call printdeps,$@,$^,$?)
	mkdir $(REPO_DIR) $(REMOTE_REPO_DIR)
	s3fs dangersalad-archlinux:/repo/x86_64 $(REMOTE_REPO_DIR) -o "nosuid,nodev,default_acl=public-read,url=https://nyc3.digitaloceanspaces.com,nomultipart"
	sleep 5
	cp $(REMOTE_DB_FILE) $(DB_FILE)
	cp $(REMOTE_FILES_FILE) $(FILES_FILE)
	cp $(patsubst %.sig,%,$?) $? $(REPO_DIR)
	cp $? $(REPO_DIR)
	for pkg in $(REPO_DIR)/*.$(PKG_SUFFIX); do repo-add $(DB_FILE) $$pkg; done
	$(call sign,$(DB_SIG),$(DB_FILE))
	$(call sign,$(FILES_SIG),$(FILES_FILE))
	cp $(DB_FILE) $(REMOTE_DB_FILE)
	cp $(FILES_FILE) $(REMOTE_FILES_FILE)
	cp $(DB_SIG) $(REMOTE_DB_SIG)
	cp $(FILES_SIG) $(REMOTE_FILES_SIG)
	for pkg in $(REPO_DIR)/*.$(PKG_SUFFIX)*; do cp $$pkg $(REMOTE_REPO_DIR); done
	sync
	$(MAKE) unmount
	touch $@
	$(call printfoot,$@)

define make_pkg_target
$(1): $(dir $(1))PKGBUILD $(call get_pkg_sources,$(1))
	$$(call printdeps,$$@,$$^,$$?)
	cd $(dir $(1)) && $(MAKEPKG)
	$$(call printfoot,$$@)
endef

$(foreach pkg,$(PKGS),$(eval $(call make_pkg_target,$(pkg))))

%.$(SIG_SUFFIX): %.$(PKG_SUFFIX)
	$(call printdeps,$@,$^,$?)
	$(call sign,$@,$<)
	$(call printfoot,$@)

clean: unmount
	rm -rf $(PKG) $(SIGS)

sync-clean: unmount
	rm -rf $(REPO_DIR) $(REMOTE_REPO_DIR)

unmount:
	-fusermount -u $(REMOTE_REPO_DIR)

.PHONE: clean unmount
