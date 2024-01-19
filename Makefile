CMD:=nix-shell -p jekyll bundler

.PHONY: shell
shell:
	$(CMD)

.PHONY: install
install:
	@$(CMD) --run "\
			bundle config set --local path vendor/cache && \
			bundle install --gemfile=Gemfile"

.PHONY: build
build:
	@$(CMD) --run "bundle exec jekyll build"

.PHONY: serve
serve:
	@$(CMD) --run "bundle exec jekyll serve --port 4000"

.PHONY: clean
clean:
	@rm -rf vendor/cache

