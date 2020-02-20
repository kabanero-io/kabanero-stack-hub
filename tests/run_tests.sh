#!/bin/bash

test_dir=$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )
base_dir=$(cd "${test_dir}/.." && pwd)
test_config_dir=$(cd "${test_dir}/test_configurations" && pwd)
if [[ ! -d "$test_dir/result_config" ]]; then
    mkdir $test_dir/result_config
fi
result_dir=$(cd "${test_dir}/result_config" && pwd)
mkdir $test_dir/exec_config
exec_config_dir=$(cd "${test_dir}/exec_config" && pwd)

expected_src_prefix="REPO_TEST_URL"

for config_file in $test_config_dir/*.yaml; do
    filename=$(basename $config_file)
    sed -e "s#{{TEST_DIR}}#${test_dir}#g" $config_file > $exec_config_dir/$filename
done

declare -a succesful_tests
declare -a failed_tests
test_count=0
for test_file in $test_dir/*_test.yaml; do
    test_filename=$(basename $test_file)
    test_filename="${test_filename%.*}"
    test_count=$((test_count+1))
    echo "Running test for configuration: $test_file"
    success="true"
    test_input=$(yq r ${test_file} input-configuration)
    test_input_file=$exec_config_dir/$test_input
    echo "test input file: $test_input_file"
    $base_dir/scripts/hub_build.sh "$test_input_file" > "$result_dir/$test_filename-output.txt"

    num_expected_results=$(yq r ${test_file} expected-results[*].output-file | wc -l)
    if [ $num_expected_results -gt 0 ] 
    then
        echo "Found $num_expected_results results"
        for ((result_count=0;result_count<$num_expected_results;result_count++)); 
        do
            # Get expected results
            result_file_name=$(yq r ${test_file} expected-results[$result_count].output-file)
            expected_stack_count=$(yq r ${test_file} expected-results[$result_count].number-of-stacks)
            expected_image_org=$(yq r ${test_file} expected-results[$result_count].image-org)
            expected_image_registry=$(yq r ${test_file} expected-results[$result_count].image-registry)
            expected_host_path=$(yq r ${test_file} expected-results[$result_count].host-path)
            declare -a included_stacks
            expected_stack_included_count=$(yq r ${test_file} expected-results[$result_count].included-stacks[*].id | wc -l)
            for ((stack_count=0;stack_count<$expected_stack_included_count;stack_count++));
            do
                included_stacks[$stack_count]=$(yq r ${test_file} expected-results[$result_count].included-stacks[$stack_count].id)
            done

            # Get actual results
            if [[ "$expected_image_registry" != null || "$expected_image_org" != null  ]]; then
                result_file=$base_dir/build/index-src/$result_file_name
                sed -e "s#{{EXTERNAL_URL}}#$expected_src_prefix#g" $result_file > $base_dir/build/index-src/temp-$result_file_name
                result_file=$base_dir/build/index-src/temp-$result_file_name
            else
                result_file=$base_dir/assets/$result_file_name
            fi
            if [[ ! -f "$result_file" ]]; then
                echo "Result file not found: $result_file"
                success="false"
                break
            fi
            results_stack_count=$(yq r ${result_file} stacks[*].id | wc -l)
            declare -a result_stacks
            declare -a image_paths
            declare -a src_paths
            for ((stack_count=0;stack_count<$results_stack_count;stack_count++));
            do
                result_stacks[$stack_count]=$(yq r ${result_file} stacks[$stack_count].id)
                image_paths[$stack_count]=$(yq r ${result_file} stacks[$stack_count].image)
                src_paths[$stack_count]=$(yq r ${result_file} stacks[$stack_count].src)
            done
            
            # Compare results
            # Check we have the right number of stacks
            if [[ $results_stack_count -ne $expected_stack_count ]]; then
                echo "  Error - Unexpected number of stacks in result"
                success="false"
            fi
            # Check all expected stacks are present
            for ((index=0;index<$expected_stack_count;index++));
            do
                expected_stack=${included_stacks[$index]}
                stack_found="false"
                for ((result_count=0;result_count<$results_stack_count;result_count++));
                do
                    result_stack=${result_stacks[$result_count]}
                    if [[ "$expected_stack" == "$result_stack" ]]; then
                        stack_found="true"
                        break
                    fi
                done
                if [[ "$stack_found" == "false" ]]; then
                    echo "  Error - Missing stack in results, stack found: $stack_found"
                    success="false"
                fi
            done
            # Check the image reistry and org are correct if overriden
            if [[ "$expected_image_registry" != null || "$expected_image_org" != null  ]]; then
            for ((result_count=0;result_count<$results_stack_count;result_count++));
                do
                    result_image=${image_paths[$result_count]}
                    IFS='/' read -a image_parts <<< "$result_image"
                    len=${#image_parts[@]}
                    if [ $len -ne 3 ]; then
                        echo "Unexpected image tag length: $result_image"
                        success="false"
                        break
                    fi
                    result_reg=${image_parts[0]}
                    result_org=${image_parts[1]}
                    if [[ "$expected_image_registry" != null ]]; then
                        if [[ "$expected_image_registry" != "$result_reg" ]]; then
                            echo "Image registry mismatch, expected: $expected_image_registry, actual: $result_reg"
                            success="false"
                            break
                        fi
                    fi
                    if [[ "$expected_image_org" != null ]]; then
                        if [[ "$expected_image_org" -ne "$result_org" ]]; then
                            echo "Image organisation mismatch, expected: $expected_image_org, actual: $result_org"
                            success="false"
                            break
                        fi
                    fi
                done
            fi
            # Check src url correctly updated
            if [[ "$expected_image_registry" != null || "$expected_image_org" != null  ]]; then
            for ((result_count=0;result_count<$results_stack_count;result_count++));
                do
                    result_src=${src_paths[$result_count]}
                    IFS='/' read -a src_parts <<< "$result_src"
                    len=${#src_parts[@]}
                    if [ $len -ne 2 ]; then
                        echo "Unexpected src path length: $result_src"
                        success="false"
                        break
                    fi
                    result_src_prefix=${src_parts[0]}
                    if [[ "$expected_src_prefix" != $result_src_prefix ]]; then
                        echo "Prefix for src mismatch, expected: $expected_src_prefix, actual: $result_src_prefix"
                        success="false"
                        break
                    fi
                done
            fi
        done
        if [[ "$success" != "true" ]]; then
            echo "Test failed: $test_input"
            failed_tests+=($test_input)
        else
            echo "Test passed: $test_input"
            succesful_tests+=($test_input)
        fi
        mv $result_file $result_dir/$result_file_name
    fi
done
rm -rf $exec_config_dir

passed_count=${#succesful_tests[@]}
echo "RESULT: $passed_count / $test_count tests passed."
if [[ $passed_count -ne $test_count ]]; then
    echo "Failed tests: ${failed_tests[*]}"
fi