# printing functions
printseptop = ┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
printsepbot = ┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛
print_template = "┃ %-100s ┃\n"
print_template_dep = "┠── %-98s ┃\n"
define printdeps = 
@echo "$(printseptop)"

@printf $(print_template) "Making $(1)"

@if [[ -n "$(2)" ]]; then \
	printf $(print_template) "depends:"; \
	for dep in $(subst $(GOPATH)/src/,,$(2)); do \
		printf $(print_template_dep) "$$dep"; \
	done; \
	printf $(print_template) "changed:"; \
	for changed in $(subst $(GOPATH)/src/,,$(3)); do \
		printf $(print_template_dep) "$$changed"; \
	done; \
fi;

@echo "$(printsepbot)"
endef

define printfoot = 
@echo "$(printseptop)"
@printf "┃ ✓ %-98s ┃\n" "Made $(1)"
@echo "$(printsepbot)"
endef

alertseptop = ╔══════════════════════════════════════════════════════════════════════════════════════════════════════╗
alertsepbot = ╚══════════════════════════════════════════════════════════════════════════════════════════════════════╝
alert_template = "║ %-100s ║\n"

define message = 
echo "$(alertseptop)"; \
echo -e "$(shell echo -n $(1))" | while read ln; do printf $(alert_template) "$$ln"; done; \
echo "$(alertsepbot)"
endef
