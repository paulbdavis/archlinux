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
REPO_DIR := $(HOME)/.cache/reposync

space :=
space +=

all: $(PKGS) $(SIGS)

sync: $(SIGS)
	$(call printdeps,$@,$^,$?)
	cp $(patsubst %.sig,%,$?) $? $(REPO_DIR)
	cp $? $(REPO_DIR)
	reposync
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
