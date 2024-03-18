#!/bin/sh

DIR_DEPTH=4      # Increase for crawling deeper than to 4 sub folders deep.
Y_COORD=1185     # Y Coordinate of the Make Integrity Test Button.
WAIT_VERDICT=12  # Verdict usually returns in 2-3 seconds, but if you decrease and verdict and it arrives later, the script will fail to read the verdict.
custom_json=/data/adb/modules/playintegrityfix/custom.pif.json  # Location of the custom.pif.json

# Do not change the code below here unless you know what you're doing
# root check, script must be ran as root. 
if [ "$USER" != "root" -o "$(whoami 2>/dev/null)" != "root" ]; then
  echo "piftest: needs root permissions";
  exit 1;
fi;

# Determine the directory of the script
case "$0" in
  *.sh) DIR="$0";;
  *) DIR="$(lsof -p $$ 2>/dev/null | grep -o '/.*piftest.sh$')";;
esac;
DIR=$(dirname "$(readlink -f "$DIR")");

# Set the FingerPrint Path
FPDIR="$1"
[ -z "$FPDIR" ] && FPDIR="$DIR"  # Use the directory of the script if no path is provided

# Create required files / logs 
list="$FPDIR/fp_list.txt";
log="$DIR/piftest_logcat.log";
xml="$DIR/testresult.xml";
resultlog="$DIR/piftest_results.log";

# Define additional variables 
spic=com.henrikherzig.playintegritychecker
gms=com.google.android.gms.unstable
integrities="NO_INTEGRITY MEETS_VIRTUAL_INTEGRITY MEETS_BASIC_INTEGRITY MEETS_DEVICE_INTEGRITY MEETS_STRONG_INTEGRITY"
bak_json="$DIR/custom.pif.bak"

rm -f "$list" # Cleanup old list files 

# Backup JSON File if there isn't already a back-up present
# Prevent overwriting your good fingerprint 
if [ ! -f "$bak_json" ]; then
  cp "$custom_json" "$bak_json"
fi

function test-json() {
    local json="$1"
    local meets=""

    cp "$json" "$custom_json"
    #rm -f "$log"
    rm -f "$xml"

    am start -n $spic/$spic.MainActivity >/dev/null 2>&1
    sleep 2

    logcat -c
    killall $gms >/dev/null 2>&1
    input tap 250 $Y_COORD

    sleep 12
    uiautomator dump "$xml" >/dev/null 2>&1
    killall $spic >/dev/null 2>&1
    logcat -d | grep PIF/ >>"$log"

    for meets in $integrities; do
        pass=$(grep -o "\"$meets\"" $xml)
        if [ ! -z "$pass" ]; then
            echo "$meets" | tee -a "$list"
            case "$meets" in
            "NO_INTEGRITY") return 0 ;; # This case can obviously never succeed, it's just here for reference
            "MEETS_VIRTUAL_INTEGRITY") return 1 ;;
            "MEETS_BASIC_INTEGRITY") return 2 ;;
            "MEETS_DEVICE_INTEGRITY") return 3 ;;
            "MEETS_STRONG_INTEGRITY") return 4 ;;
            esac
        fi
    done

    return 0 # Assume we failed, return 0 for NO_INTEGRITY
}

function test-dir() {
  ls "$1"/*.json 2>/dev/null | while read json; do
    ([ ! -n "$json" ] || [ ! -f "$json" ] || [ ! -r "$json" ]) && continue

    echo "$json" | tee -a "$list"
    
    local initial_first_api_level=$(grep -o '"FIRST_API_LEVEL": "[^"]*"' "$json" | grep -o '[0-9]*')
    local initial_device_sdk_int=$(grep -o '"DEVICE_INITIAL_SDK_INT": "[^"]*"' "$json" | grep -o '[0-9]*')
    local initial_api_level=$(grep -o '"\*api_level": "[^"]*"' "$json" | grep -o '[0-9]*')
    # Check which variable contains the API level
	if [[ -n $initial_first_api_level ]]; then
		api_level=$initial_first_api_level
	elif [[ -n $initial_device_sdk_int ]]; then
		api_level=$initial_device_sdk_int
	elif [[ -n $initial_api_level ]]; then
		api_level=$initial_api_level
	fi
	
    # Test with the initial API level
    test-json "$json"
    val=$?
    
    if [ "$val" -eq 0 ]; then
      # JSON failed integrity test, remove the file
	  echo "Deleting $json as it does not pass integrity tests"
      rm -f "$json"
    elif [ "$val" -eq 1 ]; then
      # JSON passes virtual integrity test
      : # No specific action is needed here, so we use a colon as a placeholder.
    elif [ "$val" -eq 2 ]; then
      # JSON passes basic integrity test, log the result
      echo "Basic integrity test passed for $json with API level $api_level" | tee -a "$resultlog"
      
      if [ "$initial_api_level" != "25" ] && [ "$initial_device_sdk_int" != "25" ] && [ "$initial_first_api_level" != "25" ]; then
        # Test with API level 25
        echo "Changing API Level to 25"
        sed -i 's/"FIRST_API_LEVEL": "[^"]*"/"FIRST_API_LEVEL": "25"/' "$json"
        sed -i 's/"DEVICE_INITIAL_SDK_INT": "[^"]*"/"DEVICE_INITIAL_SDK_INT": "25"/' "$json"
        sed -i 's/"\*api_level": "[^"]*"/"\*api_level": "25"/' "$json"
        test-json "$json"
        
        # Test with API level 23 if JSON passes basic integrity test with API level 25
        if [ $? -eq 2 ]; then
          echo "Basic integrity test passed for $json with API level 25" | tee -a "$resultlog"
          echo "Changing API Level to 23"
          sed -i 's/"FIRST_API_LEVEL": "[^"]*"/"FIRST_API_LEVEL": "23"/' "$json"
          sed -i 's/"DEVICE_INITIAL_SDK_INT": "[^"]*"/"DEVICE_INITIAL_SDK_INT": "23"/' "$json"
          sed -i 's/"\*api_level": "[^"]*"/"\*api_level": "23"/' "$json"
          test-json "$json"
          if [ $? -eq 2 ]; then
            echo "Basic integrity test passed for $json with API level 23" | tee -a "$resultlog"
          fi
        fi
      else
        # Test with API level 23 if the JSON initially has API level 25
        echo "API level already 25, skipping testing with API level 25" 
        echo "Changing API Level to 23"
        sed -i 's/"FIRST_API_LEVEL": "[^"]*"/"FIRST_API_LEVEL": "23"/' "$json"
        sed -i 's/"DEVICE_INITIAL_SDK_INT": "[^"]*"/"DEVICE_INITIAL_SDK_INT": "23"/' "$json"
        sed -i 's/"\*api_level": "[^"]*"/"\*api_level": "23"/' "$json"
        test-json "$json"
        if [ $? -eq 2 ]; then
          echo "Basic integrity test passed for $json with API level 23" | tee -a "$resultlog"
		  # If JSON passes basic integrity test after the final test with API 23, delete the JSON file
		  echo "Deleting $json as it only passes basic integrity test after the final test with API 23"
		  rm -f "$json"
		  fi
      fi
	elif [ "$val" -eq 3 ]; then
	  # JSON passes device integrity test, log the result
	  echo "Device integrity test passed for $json" | tee -a "$resultlog"

	  # Check if the WorkingFP folder exists, if not, create it
	  if [ ! -d "WorkingFP" ]; then
		mkdir "WorkingFP"
	  fi

	  # Copy the JSON file to the WorkingFP folder
	  cp "$json" "WorkingFP/"
	fi
  done
}

find "$FPDIR" -maxdepth $DIR_DEPTH -type d 2>/dev/null | while read testdir
do
  ([ ! -n "$testdir" ] || [ ! -e "$testdir" ]) && continue
  
  # Check for the existence of "stop.txt" file in the directory
  if [ -f "$DIR/stop.txt" ]; then
    echo "Stop signal detected. Exiting..."
    break
  fi
  
  test-dir "$testdir"
done

mv "$bak_json" "$custom_json" # Restore the original custom.pif.json
killall $gms >/dev/null 2>&1 # Kills GMS (DroidGuard) 
killall $spic >/dev/null 2>&1 # Kills Simple Play Integrity Checker
# Clean up files we no longer require
rm -f "$xml"
rm -f "$log"
