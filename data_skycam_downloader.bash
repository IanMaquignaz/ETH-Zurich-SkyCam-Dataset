#!/bin/bash

# NOTE! 
# Run this from the command line by calling the desired bash function
# for example:  . ./data_skycam_downloader.bash && download_data

# SkyCam credentials
SERVER="skycam" # options are skycam or dav (appear to be clones)
USER_NAME="INSERT_HERE"
USER_PASSWORD="INSERT_HERE"

# Slack
SLACK_SEND_MESSAGE=false #true or false
SURPRESS_DUPLICATE_MESSAGES=true #true or false
SURPRESS_VERBOSE_MESSAGES=true #true or false
SLACK_WEBHOOK="INSERT_YOUR_WEBHOOK_HERE"

# Constants
CAMERAS=('Alpnach' 'Bern1' 'Bern2' 'NE')
ARCHIVE_ZIPPED="zipped"
ARCHIVE_UNZIPPED="unzipped"
ARCHIVE_START_DATE='2018-01-01'
ARCHIVE_END_DATE='2020-01-01'

# INITS
CAMERA='NE'
SECOND="00"
MINUTE="00"
HOUR="00"
DAY="01"
MONTH="01"
YEAR="2018"
DATE=$(date -d yesterday)

# Data
EXTRACT=true #true or false

# RANGE
RANGE_DATE_START=$ARCHIVE_START_DATE
RANGE_DATE_END=$ARCHIVE_END_DATE
NEXT_GRANULES="+1" #+X for forwards -X for backward (X days). Note 6=1 week.
LAST_GRANULES="-1" #+X for forwards -X for backward (X days). Note 6=1 week.

# Send a message via the Slack webhook
SLACK_MESSAGE="Hello, World!"
function send_slackMessage {

    if [ $SLACK_SEND_MESSAGE == true ] && [ ! -z "$SLACK_MESSAGE" ]
    then
        echo sending slack message...
    
        # Sanitize
        SLACK_MESSAGE=$(echo $SLACK_MESSAGE | sed 's/"/\"/g' | sed "s/'/\'/g" )
        
        # Post the message to Slack
        curl -s -X POST -H 'Content-type: application/json' --data "{\"text\" : \"$SLACK_MESSAGE\"}" $SLACK_WEBHOOK
        # -s silent
    fi
}

# Download a range of data granules
# Note, can alternately be used to check a range of the database for holes.
function download_data_range 
{
    echo "ETH Zurich SkyCam database"
    echo "Downloading SkyCam data from $(date -d "$RANGE_DATE_START") to  $(date -d "$RANGE_DATE_END")"
    echo "Note! The date range for data granuels varies by camera. Remmember to set ARCHIVE_START_DATE and ARCHIVE_END_DATE accordingly"
    echo 

    # For each camera
    for CAMERA_ID in ${!CAMERAS[@]}
    do 
        CAMERA=${CAMERAS[$CAMERA_ID]}

        d=$RANGE_DATE_START
        d=$(date -d "$d + 4 hours") # Jump ahead to save time
        until [[ $(date -I -d "$d") > $RANGE_DATE_END ]]; do 
            
            RETRY=true # Reset retry flag

            # Set parameters for download regex
            DAY=$(date -d "$d" +'%d')
            MONTH=$(date -d "$d" +'%m')
            YEAR=$(date -d "$d" +'%Y')
            HOUR=$(date -d "$d" +'%H') # In 24h format
            MINUTE=$(date -d "$d" +'%M')
            SECOND=$(date -d "$d" +'%S')

            # Download data granule
            download_data

            # Verbose message
            if [ $SURPRESS_VERBOSE_MESSAGES == false ] 
            then 
                # Send update
                send_slackMessage 
            fi
            
            # Increment
            d_last=$d
            d=$(date -d "$d + 10 seconds")

            # Check for completeness
            if [[ $(date -I -d "$d") -ne $(date -I -d "$d_last") ]]
            then
                # For each camera
                for CAMERA_ID in ${!CAMERAS[@]}
                do 
                    CAMERA=${CAMERAS[$CAMERA_ID]}

                    fileCount=$(find zipped/ -maxdepth 1 -regex '${CAMERA}_$YEAR$MONTH${DAY}_.*.zip' | wc -l)
                    newRepoSize=$(du -h $ARCHIVE_ZIPPED | cut -f1)

                    if [ $fileCount -ge 1800 ] # The number of samples each day is inconsistent (6int*60min*5hours=1800)
                    then
                        SLACK_MESSAGE="OK :: $(date -u) :: $CAMERA SkyCam granule for $YEAR/$MONTH/$DAY downloaded successfully ($fileCount files; $newRepoSize)"
                    elif [ $fileCount == 0 ]
                    then
                        SLACK_MESSAGE="FAILED :: $(date -u) :: $CAMERA SkyCam granule for $YEAR/$MONTH/$DAY is missing ($fileCount files; $newRepoSize)"
                    else
                        SLACK_MESSAGE="FAILED :: $(date -u) :: $CAMERA SkyCam granule for $YEAR/$MONTH/$DAY is incomplete ($fileCount files; $newRepoSize)"
                    fi
                    echo $SLACK_MESSAGE

                    # Send update
                    send_slackMessage
                done

                # Bump time forwards
                d=$(date -d "$d + 5 hours")
            fi
        done
    done
}

# Download the next X granules (forwards only)
# Note, consider specifying RANGE_DATE_START
function download_data_nextX
{
    RANGE_DATE_END=$(date -I -d "$RANGE_DATE_START $NEXT_GRANULES day")
    # See INITS. NEXT_GRANULES="+6" #+X for forwards -X for backward (X days)
    
    download_data_range
}

# Download the next X granules (backwards only)
function download_data_lastX
{
    RANGE_DATE_START=$(date -I -d "$RANGE_DATE_END $LAST_GRANULES day")
    # See INITS. LAST_GRANULES="-6" #+X for forwards -X for backward (X days)
    
    download_data_range
}

# Build the dataset
function download_data_build
{
    # Get start date
    if [ $(ls $ARCHIVE_ZIPPED/*.zip | wc -l) -eq 0 ]
    then
        RANGE_DATE_START=$ARCHIVE_START_DATE
    else
        # For each camera
        lastFile="$(date -I -d "$ARCHIVE_START_DATE")"
        for CAMERA_ID in ${!CAMERAS[@]}
        do 
            CAMERA=${CAMERAS[$CAMERA_ID]}
            if [ $(ls $ARCHIVE_ZIPPED/$CAMERA*.zip | wc -l) -gt 0 ]
            then
                cut_start=$(expr ${#CAMERA} + 9)
                cut_end=$(expr $cut_start + 7)
                temp=$(date -I -d "$(ls $ARCHIVE_ZIPPED/$CAMERA*.zip | tail -n 1 | cut -c$cut_start-$cut_end)")
                if [[ "$temp" > "$lastFile" ]];
                then
                    lastFile=$temp
                fi  
            fi
        done
        RANGE_DATE_START=$(date -I -d "$lastFile +1 day") # Assume last day was complete
    fi

    # Set end date
    RANGE_DATE_END=$(date -I -d "$RANGE_DATE_START $NEXT_GRANULES day")
    # See INITS. NEXT_GRANULES="+7" #+X for forwards -X for backward (X days)
    
    download_data_range
}

# build the dataset, checking for holes in existing range
function download_data_build_check
{
    # Note, this reiterates over existing, to check for changes
    RANGE_DATE_START=$ARCHIVE_START_DATE

    # Get end date
    if [ $(ls $ARCHIVE_ZIPPED/*.zip | wc -l) -eq 0 ]
    then
        # See INITS. NEXT_GRANULES="+7" #+X for forwards -X for backward (X days)
        RANGE_DATE_END=$(date -I -d "$RANGE_DATE_START $NEXT_GRANULES day")
    else
        # For each camera
        lastFile="$(date -I -d "$ARCHIVE_START_DATE")"
        for CAMERA_ID in ${!CAMERAS[@]}
        do 
            CAMERA=${CAMERAS[$CAMERA_ID]}
            if [ $(ls $ARCHIVE_ZIPPED/$CAMERA*.zip | wc -l) -gt 0 ]
            then
                cut_start=$(expr ${#CAMERA} + 9)
                cut_end=$(expr $cut_start + 7)
                temp=$(date -I -d "$(ls $ARCHIVE_ZIPPED/$CAMERA*.zip | tail -n 1 | cut -c$cut_start-$cut_end)")
                if [[ "$temp" > "$lastFile" ]];
                then
                    lastFile=$temp
                fi
            fi
        done
        RANGE_DATE_END=$(date -I -d "$lastFile $NEXT_GRANULES day")
    fi

    download_data_range
}

# Download a data granule
function download_data {

    FILE="${CAMERA}_$YEAR$MONTH${DAY}_$HOUR-$MINUTE-$SECOND.zip"
    echo Downloading $FILE to $ARCHIVE_ZIPPED/$FILE
    
    fileExists=false
    if test -f "$ARCHIVE_ZIPPED/$FILE"; then
        echo "$ARCHIVE_ZIPPED/$FILE already exists"
        fileExists=true
    fi
    
    # Download
    wget -q --user=$USER_NAME --password=$USER_PASSWORD \
     https://portal.csem.ch:9250/$SERVER/$CAMERAS/$YEAR/$MONTH/${CAMERA}_$YEAR$MONTH${DAY}_$HOUR-$MINUTE-$SECOND.zip \
     -P $ARCHIVE_ZIPPED -N
    # -q quiet
    # -N downloads only if changed
    
    if [[ "$?" == 0 ]] # Check if wget failed
    then
        # Check Validity
        zipTestResult=$(unzip -tq $ARCHIVE_ZIPPED/$FILE)
        echo $zipTestResult
        
        if [[ $zipTestResult == *"No errors"* ]]
        then
            if [ $EXTRACT == true ]
            then
                # Unzip to archive
                unzip -uo -q $ARCHIVE_ZIPPED/$FILE -d $ARCHIVE_UNZIPPED
                # -u only extracts if new or different.
                # -o overwrite (replace different)
                # -q quiet
            fi
        
            fileSize=$(du -h $ARCHIVE_ZIPPED/$FILE | cut -f1)
            newRepoSize=$(du -h $ARCHIVE_ZIPPED | cut -f1)
            SLACK_MESSAGE="OK :: $(date -u) :: $CAMERA SkyCam granule for $YEAR/$MONTH/$DAY @ $HOUR:$MINUTE::$SECOND downloaded successfully ($fileSize/$newRepoSize)"
            echo $SLACK_MESSAGE
        else 
            rm $ARCHIVE_ZIPPED/$FILE
            if [[ $RETRY == true ]]; 
            then 
                RETRY=false
                download_data
            else
                fileExists=false # Reset flag. Send this error message
                SLACK_MESSAGE="FAILED :: $(date -u) :: $CAMERA SkyCam granule for $YEAR/$MONTH/$DAY @ $HOUR:$MINUTE::$SECOND produced a corrupt zip"
                echo $SLACK_MESSAGE
            fi
        fi
    else
        SLACK_MESSAGE="FAILED :: $(date -u) :: $CAMERA SkyCam granule for $YEAR/$MONTH/$DAY @ $HOUR:$MINUTE::$SECOND downloaded failed"
        echo $SLACK_MESSAGE
    fi
    
    # Wipe slack message if file was already downloaded
    if [ $fileExists == true ] && [ $SURPRESS_DUPLICATE_MESSAGES == true ] 
    then 
        echo Surpressing Slack message
        SLACK_MESSAGE=""
    fi
}

function unzip_data {
    if [ $EXTRACT == true ]
        then
            # Unzip to archive
            for z in $ARCHIVE_ZIPPED/*
            do 
                echo $z
                unzip -uo $z -d $ARCHIVE_UNZIPPED
                # -u only extracts if new or different
                # -o overwrite (replace different)
                # -q quiet
            done
        else
            echo skipping archive extraction
    fi
}

# TESTING
# NOTE! Uncomment the variables below only for testing

#SLACK_SEND_MESSAGE=false
#send_slackMessage

#unzip_data

#RANGE_DATE_START=2018-09-30
#RANGE_DATE_END=2018-09-30
#download_data_range
#download_data_nextX

#NEXT_GRANULES=1
#download_data_build
#download_data_build_check
