### Version 0.5.6 - (2021-10-24)

- Add exit callbacks.


### Version 0.5.5 - (2021-10-19)

- `cdenv edit <name>` now opens the file at the line where *name* is defined.


### Version 0.5.4 - (2021-10-18)

- Add name argument to 'cdenv edit'.
- Minor fixes.
- Reduce the size of the cdenv executable.


### Version 0.5.3 - (2021-10-17)

- Minor fixes.
- Remove misc/PKGBUILD.


### Version 0.5.2 - (2021-10-17)

- Enable cdenv.sh to install and update cdenv.
- Use tput instead of hardcoded ansi sequences.
- Add misc/PKGBUILD.


### Version 0.5.1 - (2021-10-16)

- Add support for `CDENV_COLOR`.


### Version 0.5.0 - (2021-10-16)

- Add support for `CDENV_AUTORELOAD`.


### Version 0.4.6 - (2021-10-14)

- Add var and array functions.
- Use more tab-completion friendly function prefix `c.`.
- Add `CDENV_CALLBACK`.
- Add `-b/--base` to edit command.


### Version 0.4.5 - (2021-10-14)

- Use `::` as function prefix instead of `__cdenv`.


### Version 0.4.4 - (2021-10-13)

- Add support for `CDENV_PATH`.
- Add stdlib functions: `on_leave`, `copy_function` and `rename_function`.
- Remove `cdenv_enter` and `cdenv_leave`.
- Minor fixes.


### Version 0.4.3 - (2021-10-13)

- Check bash scripts for errors before sourcing them.
