# RISE Build Tools

This project contains build and utility scripts to package the core code.

It's based on Docker. [Dockerfile](Dockerfile) contains the environment bootstrap while [build.sh](build.sh) is the main command used to build and package the core code.

The [build-assets/](build-assets/) folder contains several files that are bundled within the core to ease IT management.


### What does this do

The builder will create a docker environment by:

 - ensuring all compilation requirements are installed
 - bundling Node.js and installing [pm2](https://github.com/Unitech/pm2)
 - compiling Postgres 9.6.6
 - compiling Redis
 - creating folders structure.
 - copying configuration files and bash scripts needed by the bundler.

When docker image is built, tar.gz can be created by running the newly created image.


### Other scripts

The scripts folder contains the install.sh script which will let user install RISE easily.

  
