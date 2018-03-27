#!/bin/sh

# ComParE 2018, Self Assessed Affect task
# Baseline script: training on training+devel set, results on test set

# set -x

# path to your feature directory (ARFF files)
feat_dir=../arff

# directory where SVM models will be stored
model_dir=./models/traindevel_test
rm -rf $model_dir
mkdir -p $model_dir

# directory where evaluation results will be stored
eval_dir=./eval/traindevel_test
rm -rf $eval_dir
mkdir -p $eval_dir


# path to Weka's jar file
weka_jar="/tools/weka-3-8-2/weka.jar"
test -f "$weka_jar" || exit -1

# memory to allocate for the JVM
jvm_mem=12g

# SVM complexity constant
C=$1
#test -z "$C" && C_range="1.0E-1 1.0E-2 1.0E-3 1.0E-4 1.0E-5 1.0E-6"
test -z "$C" && C=1.0E-2

#epsilon-intensive loss
L=$2
test -z "$L" && L=0.1

#feature-variant
V=$3
test -z "$V" && V="fused"

if [ "$V" = "fused" ]; then
	lab_nominal=2051
	lab_numeric=2052
else
	lab_nominal=515
	lab_numeric=516
fi


# feature file basename
feat_name=ComParE2018_SelfAssessedAffect.auDeep-${V}

perl join_arffs.pl $feat_dir/$feat_name.train.arff $feat_dir/$feat_name.devel.arff $feat_dir/$feat_name.traindevel.arff  

traindevel_arff=$feat_dir/$feat_name.traindevel.arff
traindevel_arff_up=$feat_dir/$feat_name.traindevel.upsampled.arff
test_arff=$feat_dir/$feat_name.test.arff

# Upsample training set
test -f $traindevel_arff_up || perl upsample.pl $traindevel_arff $traindevel_arff_up "traindevel"

#for C in $C_range; do

	# model file name
	svm_model_name=$model_dir/$feat_name.traindevel.SMO.C$C.L$L.model

	# train SVM using Weka's SMO, using FilteredClassifier wrapper to ignore first attribute (instance name)
	if [ ! -s "$svm_model_name" ]; then
	java -Xmx$jvm_mem -classpath "$weka_jar" weka.classifiers.meta.FilteredClassifier -v -o -no-cv -c $lab_nominal -t "$traindevel_arff_up" -d "$svm_model_name" -F "weka.filters.unsupervised.attribute.Remove -R 1,2,$lab_numeric" -W weka.classifiers.functions.SMO -- -C $C -L $L -N 1 -M -P 1.0E-12 -V -1 -W 1 -K "weka.classifiers.functions.supportVector.PolyKernel -C 250007 -E 1.0" || exit 1
	fi

	echo "finished train model"

	# evaluate SVM and write predictions
	pred_file=$eval_dir/$feat_name.SMO.C$C.L$L.pred
	if [ ! -s "$pred_file" ]; then
	    java -Xmx$jvm_mem -classpath "$weka_jar" weka.classifiers.meta.FilteredClassifier -o -c $lab_nominal -l "$svm_model_name" -T "$test_arff" -p 0 -distribution > "$pred_file" || exit 1
	fi

	echo "finished evaluate SVM and write predictions"

	# produce ARFF file in submission format
	pred_arff=$eval_dir/$feat_name.SMO.C$C.L$L.arff
	if [ ! -f "$pred_arff" ]; then
		perl format_pred.pl $test_arff $pred_file $pred_arff $lab_nominal || exit 1
	fi

	echo "Created submission format ARFF: $pred_arff"

	ref_arff=$feat_dir/$feat_name.test.arff
	if [ -f "$ref_arff" ]; then
	    echo "Found reference ARFF: $ref_arff"
	    result_file=$eval_dir/`basename $pred_file .pred`.result
	    if [ ! -f $result_file ]; then
		perl score.pl $ref_arff $pred_arff $lab_nominal | tee $result_file
	    else
		cat $result_file
	    fi
	fi

#done
