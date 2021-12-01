

### version 1.8.6

* Enabled **seqfu rotate**


### version 1.8.4

* **fu-orf**
  * Fixed bug in `fu-orf` to allow for single sequences
  * Introduced `-r`, `--scan-reverse` to include reverse complement in the ORF finder
  * `fu-orf` also prints frame in the sequence comment
* Expanded test suite


### version 1.8.3

* Markdown documentation improvements
* Splashscreen for *fu-virfilter* fixed
* Argument parser for _fu-cov_ improved
* Now `seqfu --version` and `seqfu version` will print the version number and exit
* Added test for _fu-cov_
* Added citation in main command and repository


### version 1.8.2

* Added `fu-virfilter` to filter VirFinder results
* Bugfix in `seqfu cat --basename`: the last update made it working only when prefix was also specified


### version 1.8.1

* introduced `fu-homocomp` to compress homopolymers


### version 1.8.0

* added `seqfu list` to extract sequences via a list


### version 1.7.2

* `seqfu grep` supports for comments


### version 1.7.1

* **Bugfix release**: `seqfu cat` with no parameters was stripping the reads name


### version 1.7.0

* Default primer character for oligo matches in seqfu view was Unicode, now Ascii
* Updated `seqfu cat` with improved sequence id renaming handling
* Updated `seqfu grep` to report the _oligo_ matches in the output as sequence comments


### version 1.6.3

* Removed ambiguity on `-q` in `seqfu head`
* Minor documentation updates

### version 1.6.0

* Improved STDIN messages, that can be disabled by `$SEQFU_QUIET=1`
* Added `--format irida` in `seqfu metadata` (for [IRIDA uploader](https://github.com/phac-nml/irida-uploader))
* Added `--gc` in `seqfu qual`: will print an additional column with the GC content
* Minor improvements on `seqfu cat`


### version 1.5.4

* Improved STDIN messages, that can be disabled by `$SEQFU_QUIET=1`
* Minor improvements on `seqfu cat`

### version 1.5.2

* **seqfu cat** has new options to manipulate the sequence name (like `--append STRING`) and to add comments (like  `--add-len`, `--add-gc`)

### version 1.5.0

* **seqfu count** now multithreading and redesigned. The output format is identical but  the order of the records is not protected (use **seqfu count-legacy** if needed)
* **seqfu cat** can print a list of sequences matching the criteria (`--list`)

### version 1.4.0

* Added **fu-shred**
* Added  `--reverse-read` to *fu-nanotags*

# version 1.3.6

* Automatic release system
* Documentation updates
* Minor updates