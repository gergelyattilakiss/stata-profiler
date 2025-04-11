# stata-profiler

## How to use this profile file:
Save the profile file in any project using Stata. Starting Stata from that folder will initialize the setups for tracking dependencies. To be sure you use a clean sheet for package dependencies it creates and sets the ado folders to be inside your project under the folder `./ado`. There are two main commands for using the dependency tracking:
1. `project_install`
2. `install_deps`

The first installs Stata packages and adds them to a `./dependencies.yaml`.

```{stata}
project_install `pkg_name`
```

The second installs pacakges named in the file `./dependencies.yaml`.

```{Stata}
install_deps
```
