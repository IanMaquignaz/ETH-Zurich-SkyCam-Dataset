# ETH-Zurich-SkyCam-Dataset
Bash script to facilitate downloading a subset of samples from ETH Zurich SkyCam dataset. 

See Paper: [SkyCam: A Dataset of Sky Images and their Irradiance values](https://arxiv.org/abs/2105.02922).

See Dataset: [SkyCam: A Dataset of Sky Images and their Irradiance values](https://github.com/vglsd/SkyCam).

Bash usage examples [^1]:

[^1]: Suggesting using with a scheduler (eg. crontab) to incrementaly build and limit server load.

```Bash
# Build the dataset (loads the bash functions, then executes download_data_build)
./data_asi16_downloader.bash && download_data_build
```

```Bash
# Continue building on the dataset (loads the bash functions, then executes download_data_lastX)
./data_asi16_downloader.bash && download_data_lastX
```

Note, you can alter script functionality by modifying script variables from the command line. For example:
```Bash
# Loads the bash functions
./data_asi16_downloader.bash 

# Alter script variables
RANGE_DATE_START='2018-01-01'
RANGE_DATE_END='2020-01-01'

# Execute download_data_lastX
download_data_lastX
```

This can be incorporated in [crontab](https://man7.org/linux/man-pages/man5/crontab.5.html):
```Bash
# Example of job definition:
# .---------------- minute (0 - 59)
# |  .------------- hour (0 - 23)
# |  |  .---------- day of month (1 - 31)
# |  |  |  .------- month (1 - 12) OR jan,feb,mar,apr ...
# |  |  |  |  .---- day of week (0 - 6) (Sunday=0 or 7) OR sun,mon,tue,wed,thu,fri,sat
# |  |  |  |  |
# *  *  *  *  * user-name  command to be executed
01 * * * * /bin/bash -c "cd /somePath/ETH-Zurich-SkyCam-Dataset; . ./data_asi16_downloader.bash && download_data_build"
```
