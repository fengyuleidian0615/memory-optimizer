#!/bin/bash
#
# SPDX-License-Identifier: GPL-2.0
#
# Copyright (c) 2018 Intel Corporation
#
# Authors: Fengguang Wu <fengguang.wu@intel.com>
#

script_path=$(realpath $0)
script_dir=$(dirname $script_path)
tests_dir=$(dirname $script_dir)
project_dir=$(dirname $tests_dir)
cd "$tests_dir" || exit

# task-refs params on thp=never
setup_migration_thp_never_hot()
{
	loop=15
	#interval=$(echo "0.5 * $mem_gb" | bc)
	interval=0.01
}

setup_migration_thp_never_cold()
{
	loop=10
	interval=$(echo "0.5 * $mem_gb" | bc)
	interval=0.5
}

setup_migration_thp_always_hot()
{
	loop=20
	#interval=$(echo "0.01 * $mem_gb" | bc)
	interval=1
	interval=0.1
	interval=0.01
	interval=3
	interval=0.00001
}

setup_migration_thp_always_cold()
{
	loop=20
	interval=$(echo "0.01 * $mem_gb" | bc)
	interval=0.5
}

setup_sys()
{
	echo $thp > /sys/kernel/mm/transparent_hugepage/enabled
	echo 0 > /proc/sys/kernel/numa_balancing

	lsmod | grep -q kvm_ept_idle || {
		modprobe kvm
		insmod $tests_dir/kvm-ept-idle.ko
	}
}

run_migrations()
{
	local what=$1
	local i

	setup_migration_thp_${thp}_${what}
	hot_min_refs=6
	hot_min_refs=$((loop-1))
	hot_min_refs=$((loop))

	for i in $(seq 300)
	do
		sleep 1
		grep -q "Threads started" $log_file && break
	done

	#numactl -a $sysbench_pid

	sys_refs_cmd=(
		#strace
		#schedtool -R -p 20
		nice -n-20
		stdbuf -oL
		$project_dir/sys-refs
		#-vv
		-l 6
		-s 10
		#-i $interval
		-d $dram_percent
		-m $what
		-c $script_dir/sysbench-memory.yaml
		#-p $sysbench_pid
	)

        task_refs_cmd=(
		#strace
                $project_dir/task-refs
		#-vv
                -i $interval
                -d $dram_percent
                -m $what
		#-m none
                -p $sysbench_pid
        )

	#cat /proc/$sysbench_pid/smaps

	if ((1)); then
		#echo sysbench_pid: $sysbench_pid
		echo "${sys_refs_cmd[@]}"
		/usr/bin/time -v "${sys_refs_cmd[@]}"
		#| stdbuf -i0 -oL grcat $project_dir/tests/grc-conf.sys-refs
		return
	fi

	for i in 2 1 1
	do
		sleep $i
		echo
		#echo $project_dir/task-refs -l $loop -i $interval -m $what -H $hot_min_refs -p $sysbench_pid
		#time $project_dir/task-refs -l $loop -i $interval -m $what -H $hot_min_refs -p $sysbench_pid
		echo "${task_refs_cmd[@]}"
		/usr/bin/time -v "${task_refs_cmd[@]}"
		cat refs-count-$sysbench_pid
	done
}

run_test()
{
	local suffix=$1
	local mempolicy="$2"

	sysbench_cmd=(
		#numactl
		#--interleave=all

		# perf stat
		# -e dTLB-load-misses,iTLB-load-misses
		# --

		#/usr/bin/time -v

		sysbench
		#/usr/local/bin/sysbench-stats
		--time=$time
		memory
		--memory-block-size=$memory_block_size
		--memory-total-size=1024T
		--memory-scope=$memory_scope
		--memory-oper=$memory_oper
		--memory-access-mode=rnd
		--rand-type=$rand_type
		--rand-pareto-h=0.1
		--threads=$threads
		run
	)

	log_file=$log_dir/$memory_oper-$rand_type-$threads-$thp.$suffix
	exec > $log_file 2>&1

	echo numactl $mempolicy -- "${sysbench_cmd[@]}"
	time numactl $mempolicy -- "${sysbench_cmd[@]}" &
	#| stdbuf -i0 -oL grcat $project_dir/tests/grc-conf.sys-refs &

	local sysbench_pid=$!

	trap "kill $sysbench_pid; exit" SIGINT SIGQUIT

	if [[ $suffix == 'h' ]]; then
		run_migrations hot
	elif [[ $suffix == 'c' ]]; then
		run_migrations cold
	elif [[ $suffix == 'b' ]]; then
		run_migrations both
	else
		sleep 2
	fi

	grep active_anon /sys/devices/system/node/node*/vmstat

	wait
}

run_tests()
{
	setup_sys

	run_test h "--preferred=1"
	#run_test h "-m1"
	run_test 0 "-m0"
	run_test 1 "-m1"
	# run_test i "-i all"
	#run_test c "-m0"
}

log_dir=$script_dir/$(basename $0)-$(date +'%Y%m%d_%H%M%S')
mkdir -p $log_dir
cp -a $script_path $log_dir/
echo "less    $log_dir/*.?"
echo "tail -f $log_dir/*.h | grcat $project_dir/tests/grc-conf.sys-refs"

thp=always
thp=never
mem=2G
mem=64M
mem=256M
mem=1G
if ((1)); then
	memory_scope=global
	mem=128G
	mem=64G
	mem=1G
	mem=16G
	mem=32G
	mem=8G
else
	mem=256M
	mem=1G
	memory_scope=local
fi
dram_percent=25
dram_percent=45
dram_percent=55
dram_percent=99

# sysbench params
time=1800
time=600
rand_type=pareto
rand_type=gaussian
memory_oper=read
memory_block_size=$mem
threads=1
threads=8
threads=16
threads=32
threads=64
threads=1

run_tests
memory_oper=write
run_tests
# this requires adjusting interval
# thp=always
# run_tests
# memory_oper=read
# run_tests
#rand_type=zipfian
#run_tests
