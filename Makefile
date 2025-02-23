include config.mk

XAPIDOC=_build/install/default/xapi/doc
XAPISDK=_build/install/default/xapi/sdk
JOBS = $(shell getconf _NPROCESSORS_ONLN)
PROFILE=release
XAPI_VERSION ?= $(shell git describe --always --dirty || echo "NO_GIT")
MANDIR ?= $(OPTDIR)/man/man1/

.PHONY: build clean test doc python format list-hd install uninstall

build:
	XAPI_VERSION=$(XAPI_VERSION) dune build @install -j $(JOBS) --profile=$(PROFILE)

# Quickly verify that the code compiles, without actually building it
check:
	XAPI_VERSION=$(XAPI_VERSION) dune build @check -j $(JOBS) --profile=$(PROFILE)

clean:
	dune clean

test:
	XAPI_VERSION=$(XAPI_VERSION) dune runtest --profile=$(PROFILE) --no-buffer -j $(JOBS)

doc:
	XAPI_VERSION=$(XAPI_VERSION) dune build --profile=$(PROFILE) ocaml/idl/datamodel_main.exe
	dune build --profile=$(PROFILE) -f @ocaml/doc/jsapigen
	mkdir -p $(XAPIDOC)/html
	cp -r _build/default/ocaml/doc/api $(XAPIDOC)/html
	cp _build/default/ocaml/doc/branding.js $(XAPIDOC)/html
	cp ocaml/doc/*.js ocaml/doc/*.html ocaml/doc/*.css $(XAPIDOC)/html
	dune exec --profile=$(PROFILE) -- ocaml/idl/datamodel_main.exe -closed -markdown $(XAPIDOC)/markdown
	cp ocaml/doc/*.dot ocaml/doc/doc-convert.sh $(XAPIDOC)
	find ocaml/doc -name "*.md" -not -name "README.md" -exec cp {} $(XAPIDOC)/markdown/ \;

sdk:
	cp $(SHAREDIR)/sm/XE_SR_ERRORCODES.xml ocaml/sdk-gen/csharp/XE_SR_ERRORCODES.xml
	dune build --profile=$(PROFILE) \
		ocaml/sdk-gen/c/gen_c_binding.exe \
		ocaml/sdk-gen/csharp/gen_csharp_binding.exe \
		ocaml/sdk-gen/java/main.exe \
		ocaml/sdk-gen/powershell/gen_powershell_binding.exe
	dune build --profile=$(PROFILE) -f\
		@ocaml/sdk-gen/c/generate \
		@ocaml/sdk-gen/csharp/generate \
		@ocaml/sdk-gen/java/generate \
		@ocaml/sdk-gen/powershell/generate
	mkdir -p $(XAPISDK)/c
	mkdir -p $(XAPISDK)/csharp
	mkdir -p $(XAPISDK)/java
	mkdir -p $(XAPISDK)/powershell
	mkdir -p $(XAPISDK)/python
	cp -r _build/default/ocaml/sdk-gen/c/autogen/* $(XAPISDK)/c
	cp -r _build/default/ocaml/sdk-gen/csharp/autogen/* $(XAPISDK)/csharp
	cp -r _build/default/ocaml/sdk-gen/java/autogen/* $(XAPISDK)/java
	cp -r _build/default/ocaml/sdk-gen/powershell/autogen/* $(XAPISDK)/powershell
	cp -r ocaml/sdk-gen/python/samples $(XAPISDK)/python
	cp scripts/examples/python/XenAPI/XenAPI.py $(XAPISDK)/python
	sh ocaml/sdk-gen/windows-line-endings.sh $(XAPISDK)/csharp
	sh ocaml/sdk-gen/windows-line-endings.sh $(XAPISDK)/powershell

python:
	$(MAKE) -C scripts/examples/python build

doc-json:
	dune build --profile=$(PROFILE) ocaml/idl/json_backend/gen_json.exe
	dune exec --profile=$(PROFILE) -- ocaml/idl/json_backend/gen_json.exe -destdir _build/install/default/jekyll

format:
	dune build @fmt --auto-promote

list-hd:
	LIST_HD=$$(git grep -r --count 'List.hd' -- **/*.ml | cut -d ':' -f 2 | paste -sd+ - | bc) ;\
	echo counted $$LIST_HD usages ;\
	test $$LIST_HD -eq 300

verify-cert:
	@NONE=$$( git grep -r --count 'verify_cert:None' -- **/*.ml | cut -d ':' -f 2 | paste -sd+ - | bc) ;\
	echo "counted $$NONE usages of verify_cert:None" ;\
	test $$NONE -eq 6

quality-gate: list-hd verify-cert ;

install: build doc sdk
	mkdir -p $(DESTDIR)$(SBINDIR)
	mkdir -p $(DESTDIR)$(OPTDIR)/bin
	mkdir -p $(DESTDIR)$(MANDIR)
	mkdir -p $(DESTDIR)$(LIBEXECDIR)
	mkdir -p $(DESTDIR)$(OPTDIR)/debug
	mkdir -p $(DESTDIR)/usr/bin
	mkdir -p $(DESTDIR)/etc/bash_completion.d
# ocaml/xapi
	make -C scripts install
	cp -f _build/install/default/bin/xapi $(DESTDIR)$(SBINDIR)/xapi
	scripts/install.sh 755 ocaml/quicktest/quicktest $(DESTDIR)$(OPTDIR)/debug
	cp -f _build/install/default/bin/quicktestbin $(DESTDIR)$(OPTDIR)/debug/quicktestbin
	scripts/install.sh 644 _build/install/default/share/xapi/rbac_static.csv $(DESTDIR)$(OPTDIR)/debug
# ocaml/xsh
	cp -f _build/install/default/bin/xsh $(DESTDIR)$(OPTDIR)/bin/xsh
# ocaml/xe-cli
	scripts/install.sh 755 _build/install/default/bin/xe $(DESTDIR)$(OPTDIR)/bin/xe
	ln -sf $(OPTDIR)/bin/xe $(DESTDIR)/usr/bin/xe
	scripts/install.sh 755 ocaml/xe-cli/bash-completion $(DESTDIR)/etc/bash_completion.d/xe
# ocaml/vncproxy
	scripts/install.sh 755 _build/install/default/bin/vncproxy $(DESTDIR)$(OPTDIR)/debug/vncproxy
# ocaml/perftest
	scripts/install.sh 755 _build/install/default/bin/perftest $(DESTDIR)$(OPTDIR)/debug/perftest
# ocaml/mpathalert
	scripts/install.sh 755 _build/install/default/bin/mpathalert $(DESTDIR)$(OPTDIR)/bin/mpathalert
# ocaml/license
	scripts/install.sh 755 _build/install/default/bin/daily-license-check $(DESTDIR)$(LIBEXECDIR)/daily-license-check
# ocaml/alerts/certificate
	scripts/install.sh 755 _build/install/default/bin/alert-certificate-check $(DESTDIR)$(LIBEXECDIR)/alert-certificate-check
# ocaml/events
	scripts/install.sh 755 _build/install/default/bin/event_listen $(DESTDIR)$(OPTDIR)/debug/event_listen
# ocaml/db_process
	scripts/install.sh 755 _build/install/default/bin/xapi-db-process $(DESTDIR)$(OPTDIR)/bin/xapi-db-process
# ocaml/cdrommon
	scripts/install.sh 755 _build/install/default/bin/cdrommon $(DESTDIR)$(LIBEXECDIR)/cdrommon
# ocaml/database
	scripts/install.sh 755 _build/install/default/bin/block_device_io $(DESTDIR)$(LIBEXECDIR)/block_device_io
# ocaml/gencert
	scripts/install.sh 755 _build/install/default/bin/gencert $(DESTDIR)$(LIBEXECDIR)/gencert
# ocaml/rrd2csv
	scripts/install.sh 755 _build/install/default/bin/rrd2csv $(DESTDIR)$(OPTDIR)/bin/rrd2csv
	scripts/install.sh 644 ocaml/rrd2csv/man/rrd2csv.1.man $(DESTDIR)$(MANDIR)/rrd2csv.1
# Libraries
	dune install --profile=$(PROFILE) \
		xapi-client xapi-database xapi-consts xapi-cli-protocol xapi-datamodel xapi-types
# docs
	mkdir -p $(DESTDIR)$(DOCDIR)
	cp -r $(XAPIDOC)/html $(DESTDIR)$(DOCDIR)
	cp -r $(XAPIDOC)/markdown $(DESTDIR)$(DOCDIR)
	cp $(XAPIDOC)/*.dot $(XAPIDOC)/doc-convert.sh $(DESTDIR)$(DOCDIR)
# sdk
	mkdir -p $(DESTDIR)$(SDKDIR)
	cp -r $(XAPISDK)/* $(DESTDIR)$(SDKDIR)
	find $(DESTDIR)$(SDKDIR) -type f -exec chmod 644 {} \;

uninstall:
	# only removes the libraries, which were installed with `dune install`
	dune uninstall xapi-client xapi-database xapi-consts xapi-cli-protocol xapi-datamodel xapi-types
