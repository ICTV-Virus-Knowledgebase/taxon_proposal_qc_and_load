#!/usr/bin/env bash
#
# process MSL39v4 (./Pending_Proposals | ./proposalsFinal)
#
# USAGE: ./process.sh [test_pattern] [container_version]
#
# On Linux, this runs the docker container
# On MacOS, this runs R directly. 
#

# which tests to run 
TEST_PAT="Pending_Proposals"; RUN_MODE="draft" # [validate], draft, final
TEST_PAT="proposalsFinal";    RUN_MODE="final" # [validate], draft, final
#TEST_PAT="2023.017P*.xlsx"
echo TEST_PAT=$TEST_PAT

echo "RUN_MODE=$RUN_MODE"

# 
# where are we
#
RUN_DIR=$(basename $(pwd))

# pass-through args
MSL_NOTES="DRAFT EC55 v5 MSL. EC Use Only DRAFT (to-be MSL 39); Updated 2024-03-22.0000"
SCRIPT_ARGS="--msl --mode=$RUN_MODE --newMslName=2023 "
#SCRIPT_ARGS='--msl --mode=draft --newMslName=2023 --newMslNotes="EC55 Draft 2023-07-18 (MSL 39v5-draft)" '
if [ ! -z "$1" ]; then SCRIPT_ARGS="$SCRIPT_ARGS $*"; fi
echo SCRIPT_ARGS=$SCRIPT_ARGS

# which docker container to run
if [ "$(uname)" == "Linux" ]; then 
	CONTAINER=ictv_proposal_processor
	if [ ! -z "$1" ]; then CONTAINER="curtish/${CONTAINER}:$1"; shift; fi
	echo "CONTAINER=$CONTAINER"

	# 
	# update docker image, just incase
	#
	echo "# Building docker image"
	echo \(cd ..;./docker_build_image.sh\)
	(cd ..; ./docker_build_image.sh)

	#
	# run in this dir, not ..
	#
	RUN_DIR=.
fi
echo "RUN_DIR=$RUN_DIR"

#
# test cases location
# 
TEST_DIR=.
echo TEST_DIR=$TEST_DIR
RESULTS_DIR=results
if [ ! -z "$CONTAINER" ]; then
    RESULTS_DIR=testResultsDocker
fi
echo RESULTS_DIR=$RESULTS_DIR

REPORT=EC55.regression_test.summary.txt
echo REPORT=$REPORT
(date; hostname) > $REPORT

#
# scan for test directories
#
#echo "#$ find $TEST_DIR -type d -name "$TEST_PAT" -exec basename {} \;"
#TESTS=$(find $TEST_DIR -type d -name "$TEST_PAT" -exec basename {} \;)
echo "#$ find $TEST_DIR  -name \"$TEST_PAT\" -exec basename {} \; | sort | uniq"
TESTS=$(find $TEST_DIR -name "$TEST_PAT" -exec basename {} \; | sort | uniq)
echo TESTS=$TESTS

#
# iterate
#
for TEST in $TESTS; do
    #
    # input/output for script
    #
    SRC_DIR=$TEST_DIR/$TEST
    DEST_DIR=${RESULTS_DIR}/$TEST
    RESULTS=${DEST_DIR}/QC.regression.new.tsv
    RESULTSBASE=${DEST_DIR}/QC.regression.tsv
    RESULTSDIFF=${DEST_DIR}/QC.regression.diff
    RESULTSDWDIFF=${DEST_DIR}/QC.regression.dwdiff
    LOG=${DEST_DIR}/log.new.txt
    LOGBASE=${DEST_DIR}/log.txt
    LOGDIFF=${DEST_DIR}/log.diff

    mkdir -p $DEST_DIR
    #
    # header
    #
    echo "#########################################"
    echo "###### $TEST "
    echo "#########################################"
    echo SRC_DIR=$SRC_DIR
    echo DEST_DIR=$DEST_DIR
    echo RESULTS=$RESULTS
    echo RESULTSBASE=$RESULTSBASE
    echo LOG=$LOG

    #
    # run script
    #
    if [ -z "$CONTAINER" ]; then 
	# scripts must run in ".."
        (
	    cd ..
	    
	    # update code/git version string
	    ./version_git.sh

	    # print command
	    echo "#" \
	        Rscript ./merge_proposal_zips.R \
		    --mode=$RUN_MODE \
		    --proposalsDir=$RUN_DIR/$SRC_DIR \
		    --outDir=$RUN_DIR/$DEST_DIR \
		    --qcTsvRegression=$(basename $RESULTS) \
		    --qcTsvRegression=$(basename $RESULTS) \
		    --newMslNotes="$MSL_NOTES" \
		    $SCRIPT_ARGS \
		    2>&1 | tee $RUN_DIR/$LOG
	    # run command
	    Rscript ./merge_proposal_zips.R \
		    --mode=$RUN_MODE \
		    --proposalsDir=$RUN_DIR/$SRC_DIR \
		    --outDir=$RUN_DIR/$DEST_DIR \
		    --qcTsvRegression=$(basename $RESULTS) \
		    --newMslNotes="$MSL_NOTES" \
		    $SCRIPT_ARGS \
		    2>&1 | tee -a $RUN_DIR/$LOG
	    echo "DONE ./merge_proposal_zips.R"
	)
    else
	   echo "#" \
		sudo docker run -it \
		    -v "$(pwd)/$TEST_DIR:/testData":ro \
		    -v "$(pwd)/$RESULTS_DIR:/testResults":rw \
	            $CONTAINER  \
		    /merge_proposal_zips.R \
		    --mode=$RUN_MODE \
		    --proposalsDir=$SRC_DIR \
		    --outDir="testResults/$TEST" \
		    --qcTsvRegression=$(basename $RESULTS) \
		    $SCRIPT_ARGS \
		    2>&1 | tee $LOG
	    sudo docker run -it \
		    -v "$(pwd)/$TEST_DIR:/testData":ro \
		    -v "$(pwd)/$RESULTS_DIR:/testResults":rw \
	            $CONTAINER  \
		    /merge_proposal_zips.R \
		    --mode=$RUN_MODE \
		    --proposalsDir=$SRC_DIR \
		    --outDir="testResults/$TEST" \
		    --qcTsvRegression=$(basename $RESULTS) \
		    $SCRIPT_ARGS \
		    2>&1 >> $LOG
	    echo "DONE ./merge_proposal_zips.R"
    fi	

    #
    # check output
    #
    echo "dwdiff --color  <(cut -f 5- $RESULTSBASE) <(cut -f 5- $RESULTS) #> $RESULTSDWDIFF" | tee $RESULTSDWDIFF
    dwdiff --color <(cut -f 5- $RESULTSBASE) <(cut -f 5- $RESULTS) 2>&1 >> $RESULTSDWDIFF; RC=$?
    echo "diff -yw -W 200 \<(cut -f 5- $RESULTS) \<(cut -f 5- $RESULTSBASE) \> $RESULTSDIFF" | tee $RESULTSDIFF
    diff -yw -W 200 <(cut -f 5- $RESULTS) <(cut -f 5- $RESULTSBASE) 2>&1 >> $RESULTSDIFF; RC=$?
    if [ $RC -eq "0" ]; then
	echo "PASS  $TEST" | tee -a $REPORT
    else
	echo "FAIL$RC $TEST" | tee -a $REPORT
    fi	

    #
    # check log
    #
    # use "tail -n +3" to skip date/version/etc in first 2 lines
    #
    echo "diff -yw -W 200 \<(tail -n +3 $LOG) \<(tail -n +3 $LOGBASE) \> $LOGDIFF" | tee $LOGDIFF
    diff -yw -W 200 <(tail -n +3 $LOG) <(tail -n +3 $LOGBASE) 2>&1 >> $LOGDIFF; RC=$?
    if [ $RC -eq "0" ]; then
	echo "LOG_PASS  $TEST" | tee -a $REPORT
    else
	echo "LOG_FAIL$RC $TEST" | tee -a $REPORT
    fi
    echo "#-------------------------" | tee -a $REPORT
	
done
echo "#########################################"
echo "############### SUMMARY ################# "
echo "#########################################"
cat $REPORT
   