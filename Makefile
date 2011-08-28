#
# TagmaDebug - Interactive TCL Debugger
#
# This file is in the public domain.
#
# For more information contact Lorance Stinson AT Gmail...
# Or see https://github.com/LStinson/TagmaDebug

# Change to where you want the debugger installed.
prefix		= /usr/local
bin		= $(prefix)/bin
mandir		= $(prefix)/man
man1dir		= $(mandir)/man1

# Distribution files.
EXECUTABLE	= tagmadebug
MAN		= tagmadebug.man1
POD		= man.pod
README 		= README
DOCS		= $(README) $(MAN)
SOURCE		= tagmadebug.tcl
DISTFILES       = $(MAN) $(POD) $(README) $(SOURCES)
DIST_DIR	= tagmadebug

# Generated files.
CLEAN_FILES	= $(MAN) $(README)

# Display help text based on the comments in Makefile.
help:
	@awk ' \
		BEGIN { \
			format="%-10s %s"; \
			printf format "\n", "Command", "Action"; \
		} \
		/^#/ {	sub(/^# */,""); \
			if (comments) { \
				comments=comments "\n" sprintf(format, "", $$0); \
			} else { \
				comments=$$0; \
			} \
		} \
		! $$0 {comments=""} \
		/^[0-9a-z][0-9a-z]*:/ && comments { \
			sub(/:$$/,"",$$1); \
			printf format "\n", $$1, comments; \
			comments=""; \
		} \
	' Makefile

# Clean up generated files.
clean:
	rm -f $(CLEAN_FILES)

# Install the excutable and manual.
install: man
	cp $(SOURCE) $(bin)/$(EXECUTABLE)
	cp $(MAN) $(man1dir)

# Update files for GIT.
git: $(DOCS)

# Package the files up for distribution.
dist: $(DOCS)
	mkdir $(DIST_DIR)
	cp -pR $(DISTFILES) $(DIST_DIR)
	tar -cf - $(DIST_DIR)/ | gzip -9 > $(DIST_DIR).tar.gz
	zip -r $(DIST_DIR).zip $(DIST_DIR)/
	rm -rf $(DIST_DIR)

# Generate the manual file.
man: $(POD)
	pod2man $(POD) > $(MAN)

# Generate the README file.
readme:	$(POD)
	pod2text $(POD) > $(README)

$(MAN): man

$(README): readme
