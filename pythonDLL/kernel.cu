//  Microsoft
#define DLLEXPORT extern "C" __declspec(dllexport)

#include "cuda_runtime.h"
#include "device_launch_parameters.h"

#include <stdio.h>

#include <iostream>
#include <vector>
#include <map>

#include "H5Cpp.h"
#include <H5Exception.h>

#include <Python.h>

#include <omp.h>

const int max_tags_length = 200000;
const int max_clock_tags_length = 5000;
const int max_channels = 3;
const size_t return_size = 3;
const int file_block_size = 16;
const double tagger_resolution = 82.3e-12;
const int num_gpu = 2;
const int threads_per_cuda_block_numer = 64;
const int shared_mem_size = 4;

struct shotData {
	bool file_load_completed;
	std::vector<short int> channel_list;
	std::map<short int, short int> channel_map;
	std::vector<long long int> start_tags;
	std::vector<long long int> end_tags;
	std::vector<long long int> photon_tags;
	std::vector<long long int> clock_tags;
	std::vector<std::vector<long long int>> sorted_photon_tags;
	std::vector<std::vector<long int>> sorted_photon_bins;
	std::vector<std::vector<long long int>> sorted_clock_tags;
	std::vector<std::vector<long int>> sorted_clock_bins;
	std::vector<long int> sorted_photon_tag_pointers;
	std::vector<long int> sorted_clock_tag_pointers;

	shotData() : sorted_photon_tags(max_channels, std::vector<long long int>(max_tags_length, 0)), sorted_photon_bins(max_channels, std::vector<long int>(max_tags_length, 0)), sorted_photon_tag_pointers(max_channels, 0), sorted_clock_tags(2, std::vector<long long int>(max_clock_tags_length, 0)), sorted_clock_bins(2, std::vector<long int>(max_clock_tags_length, 0)), sorted_clock_tag_pointers(2, 0) {}
};

struct gpuData {
	long int *coinc_gpu;
	long int *photon_bins_gpu;
	long int *start_and_end_clocks_gpu;
	int *max_bin_gpu, *pulse_spacing_gpu, *max_pulse_distance_gpu, *photon_bins_length_gpu;
	int *offset_gpu;
};

__global__ void calculateCoincidencesGPU_g2(long int *coinc, long int *photon_bins, long int *start_and_end_clocks, int *max_bin, int *pulse_spacing, int *max_pulse_distance, int *offset, int *photon_bins_length, int num_channels, int shot_file_num) {
	//Get numerator step to work on
	int id = threadIdx.x;
	int block = blockIdx.x;
	int block_size = blockDim.x;

	//Check we're not calculating something out of range
	if (block * block_size + id < ((*max_bin * 2 + 1) + (*max_pulse_distance * 2))) {
		int pulse_shift_measurment = (block * block_size + id >= *max_bin * 2 + 1) && (block * block_size + id < *max_bin * 2 + 1 + (*max_pulse_distance * 2));
		int pulse_shift = ((block * block_size + id - (*max_bin * 2 + 1) - (*max_pulse_distance)) + ((block * block_size + id - (*max_bin * 2 + 1) - (*max_pulse_distance)) >= 0)) * (pulse_shift_measurment);
		int tau = (block * block_size + id - (*max_bin)) * (!pulse_shift_measurment);
		tau += pulse_shift * (*pulse_spacing);
		for (int channel_1 = 0; channel_1 < num_channels; channel_1++) {
			for (int channel_2 = channel_1 + 1; channel_2 < num_channels; channel_2++) {
				int i = 0;
				int j = 0;
				int running_tot = 0;
				while ((i < photon_bins_length[channel_1 + shot_file_num * max_channels]) && (j < photon_bins_length[channel_2 + shot_file_num * max_channels])) {
					//Check if we're outside the window of interest
					int out_window = (photon_bins[offset[channel_1 + shot_file_num * max_channels] + i] < (*max_bin + *max_pulse_distance * *pulse_spacing + start_and_end_clocks[0 + shot_file_num * 2])) || (photon_bins[offset[channel_1 + shot_file_num * max_channels] + i] > (start_and_end_clocks[1 + shot_file_num * 2] - (*max_bin + *max_pulse_distance * *pulse_spacing)));
					//Increment i if chan_1 < chan_2
					int c1gc2 = !out_window && (photon_bins[offset[channel_1 + shot_file_num * max_channels] + i] < (photon_bins[offset[channel_2 + shot_file_num * max_channels] + j] - tau));
					//Check if we have a common element increment
					int c1ec2 = !out_window && (photon_bins[offset[channel_1 + shot_file_num * max_channels] + i] == (photon_bins[offset[channel_2 + shot_file_num * max_channels] + j] - tau));
					//Increment running total if channel 1 equals channel 2
					running_tot += c1ec2;
					//Increment channel 1 if it is greater than channel 2, equal to channel 2 or ouside of the window
					i += (c1gc2 + c1ec2 + out_window);
					j += !(c1gc2 + c1ec2 + out_window) + c1ec2;
				}
				coinc[block * block_size + id + shot_file_num * ((*max_bin * 2 + 1) + (*max_pulse_distance * 2))] += running_tot;
			}
		}
	}
}

__global__ void calculateCoincidencesGPU_g2_test2(long int *coinc, long int *photon_bins, long int *start_and_end_clocks, int *max_bin, int *pulse_spacing, int *max_pulse_distance, int *offset, int *photon_bins_length, int num_channels, int shot_file_num) {
	//Get numerator step to work on
	int id = threadIdx.x;
	int block = blockIdx.x;
	int block_size = blockDim.x;

	//Check we're not calculating something out of range
	if (block * block_size + id < ((*max_bin * 2 + 1) + (*max_pulse_distance * 2))) {
		int pulse_shift_measurment = (block * block_size + id >= *max_bin * 2 + 1) && (block * block_size + id < *max_bin * 2 + 1 + (*max_pulse_distance * 2));
		int pulse_shift = ((block * block_size + id - (*max_bin * 2 + 1) - (*max_pulse_distance)) + ((block * block_size + id - (*max_bin * 2 + 1) - (*max_pulse_distance)) >= 0)) * (pulse_shift_measurment);
		int tau = (block * block_size + id - (*max_bin)) * (!pulse_shift_measurment);
		tau += pulse_shift * (*pulse_spacing);
		for (int channel_1 = 0; channel_1 < num_channels; channel_1++) {
			for (int channel_2 = channel_1 + 1; channel_2 < num_channels; channel_2++) {
				int i = 0;
				int j = 0;
				int running_tot = 0;
				while ((i < photon_bins_length[channel_1 + shot_file_num * max_channels]) && (j < photon_bins_length[channel_2 + shot_file_num * max_channels])) {
					//Check if we're outside the window of interest
					int out_window = (photon_bins[offset[channel_1 + shot_file_num * max_channels] + i] < (*max_bin + *max_pulse_distance * *pulse_spacing + start_and_end_clocks[0 + shot_file_num * 2])) || (photon_bins[offset[channel_1 + shot_file_num * max_channels] + i] > (start_and_end_clocks[1 + shot_file_num * 2] - (*max_bin + *max_pulse_distance * *pulse_spacing)));
					//Increment i if chan_1 < chan_2
					int c1gc2 = (photon_bins[offset[channel_1 + shot_file_num * max_channels] + i] < (photon_bins[offset[channel_2 + shot_file_num * max_channels] + j] - tau));
					//Check if we have a common element increment
					int c1ec2 = (photon_bins[offset[channel_1 + shot_file_num * max_channels] + i] == (photon_bins[offset[channel_2 + shot_file_num * max_channels] + j] - tau));
					//Increment running total if channel 1 equals channel 2
					running_tot += !out_window && c1ec2;
					//Increment channel 1 if it is greater than channel 2, equal to channel 2 or ouside of the window
					i += (c1gc2 || c1ec2 || out_window);
					j += !c1gc2;
				}
				coinc[block * block_size + id + shot_file_num * ((*max_bin * 2 + 1) + (*max_pulse_distance * 2))] += running_tot;
			}
		}
	}
}

//__device__ void loadToShared(long int *photon_bins, long int *photons_bins_a, long int *photons_bins_b, int i, int j, int id) {
//	for (int dummy = 0; dummy < shared_mem_size; dummy++) {
//		photons_bins_a[dummy + id * shared_mem_size] = photon_bins[i + dummy];
//	}
//	for (int dummy = 0; dummy < shared_mem_size; dummy++) {
//		photons_bins_b[dummy + id * shared_mem_size] = photon_bins[j + dummy];
//	}
//}

__global__ void calculateCoincidencesGPU_g2_test(long int *coinc, long int *photon_bins, long int *start_and_end_clocks, int *max_bin, int *pulse_spacing, int *max_pulse_distance, int *offset, int *photon_bins_length, int num_channels, int shot_file_num) {
	//Get numerator step to work on
	int id = threadIdx.x;
	int block = blockIdx.x;
	int block_size = blockDim.x;

	int max_bin_gpu = *max_bin;
	int pulse_spacing_gpu = *pulse_spacing;
	int max_pulse_distance_gpu = *max_pulse_distance;
	int num_channels_gpu = num_channels;
	int shot_file_num_gpu = shot_file_num;
	__shared__ long int photons_bins_a[shared_mem_size * threads_per_cuda_block_numer];
	__shared__ long int photons_bins_b[shared_mem_size * threads_per_cuda_block_numer];

	//Check we're not calculating something out of range
	if (block * block_size + id < ((max_bin_gpu * 2 + 1) + (max_pulse_distance_gpu * 2))) {
		int pulse_shift_measurment = (block * block_size + id >= max_bin_gpu * 2 + 1) && (block * block_size + id < max_bin_gpu * 2 + 1 + (max_pulse_distance_gpu * 2));
		int pulse_shift = ((block * block_size + id - (max_bin_gpu * 2 + 1) - (max_pulse_distance_gpu)) + ((block * block_size + id - (max_bin_gpu * 2 + 1) - (max_pulse_distance_gpu)) >= 0)) * (pulse_shift_measurment);
		int tau = (block * block_size + id - (max_bin_gpu)) * (!pulse_shift_measurment);
		long int start_clock = start_and_end_clocks[0 + shot_file_num * 2];
		long int end_clock = start_and_end_clocks[1 + shot_file_num * 2];
		
		tau += pulse_shift * (pulse_spacing_gpu);
		for (int channel_1 = 0; channel_1 < num_channels_gpu; channel_1++) {
			for (int channel_2 = channel_1 + 1; channel_2 < num_channels_gpu; channel_2++) {
				int i = 0;
				int j = 0;
				int l_a = photon_bins_length[channel_1 + shot_file_num_gpu * max_channels];
				int l_b = photon_bins_length[channel_2 + shot_file_num_gpu * max_channels];
				int running_tot = 0;
				while ((i < l_a) && (j < l_b)) {
					int i_a = 0;
					int j_b = 0;
					int out_window;
					int c1lc2;
					int c1ec2;
					//Load up from global to shared memory some bins
					#pragma unroll
					for (int dummy = 0; dummy < shared_mem_size; dummy++) {
						photons_bins_a[dummy + id * shared_mem_size] = photon_bins[offset[channel_1 + shot_file_num_gpu * max_channels] + i + dummy];
					}
					#pragma unroll
					for (int dummy = 0; dummy < shared_mem_size; dummy++) {
						photons_bins_b[dummy + id * shared_mem_size] = photon_bins[offset[channel_2 + shot_file_num_gpu * max_channels] + j + dummy];
					}
					while ((i_a < shared_mem_size) && (j_b < shared_mem_size) && (i_a + i < l_a) && (j_b + j < l_b)) {
						//Check if we're outside the window of interest
						out_window = (photons_bins_a[i_a + id * shared_mem_size] < (max_bin_gpu + max_pulse_distance_gpu * pulse_spacing_gpu + start_clock)) || (photons_bins_a[i_a + id * shared_mem_size] > (end_clock - (max_bin_gpu + max_pulse_distance_gpu * pulse_spacing_gpu)));
						//Increment i if chan_1 < chan_2
						c1lc2 = (photons_bins_a[i_a + id * shared_mem_size] < (photons_bins_b[j_b + id * shared_mem_size] - tau));
						//Check if we have a common element increment
						c1ec2 = (photons_bins_a[i_a + id * shared_mem_size] == (photons_bins_b[j_b + id * shared_mem_size] - tau));
						//Increment running total if channel 1 equals channel 2
						running_tot += !(out_window) && c1ec2;
						//Increment channel 1 if it is greater than channel 2, equal to channel 2 or ouside of the window
						i_a += (c1lc2 || c1ec2 || out_window);
						j_b += !c1lc2;
					}
					i += i_a;
					j += j_b;
				}
				coinc[block * block_size + id + shot_file_num_gpu * ((max_bin_gpu * 2 + 1) + (max_pulse_distance_gpu * 2))] += running_tot;
			}
		}
	}
}

__global__ void calculateCoincidencesGPU_g2_channelPair(long int *coinc, long int *photon_bins, long int *start_and_end_clocks, int *max_bin, int *pulse_spacing, int *max_pulse_distance, int *offset, int *photon_bins_length, int channel_1, int channel_2, int shot_file_num) {
	//Get numerator step to work on
	int id = threadIdx.x;
	int block = blockIdx.x;
	int block_size = blockDim.x;

	//Check we're not calculating something out of range
	if (block * block_size + id < ((*max_bin * 2 + 1) + (*max_pulse_distance * 2))) {
		int pulse_shift_measurment = (block * block_size + id >= *max_bin * 2 + 1) && (block * block_size + id < *max_bin * 2 + 1 + (*max_pulse_distance * 2));
		int pulse_shift = ((block * block_size + id - (*max_bin * 2 + 1) - (*max_pulse_distance)) + ((block * block_size + id - (*max_bin * 2 + 1) - (*max_pulse_distance)) >= 0)) * (pulse_shift_measurment);
		int tau = (block * block_size + id - (*max_bin)) * (!pulse_shift_measurment);
		tau += pulse_shift * (*pulse_spacing);
		int i = 0;
		int j = 0;
		int running_tot = 0;
		while ((i < photon_bins_length[channel_1 + shot_file_num * max_channels]) && (j < photon_bins_length[channel_2 + shot_file_num * max_channels])) {
			int dummy_i = 0;
			int dummy_j = 0;
			int out_window = 0;
			//Increment i if we're outside the window of interest
			out_window = (photon_bins[offset[channel_1 + shot_file_num * max_channels] + i] < (*max_bin + *max_pulse_distance * *pulse_spacing + start_and_end_clocks[0 + shot_file_num * 2])) || (photon_bins[offset[channel_1 + shot_file_num * max_channels] + i] > (start_and_end_clocks[1 + shot_file_num * 2] - (*max_bin + *max_pulse_distance * *pulse_spacing)));
			//in_window = (photon_bins[offset[channel_1] + i] < (*max_bin + *max_pulse_distance * *pulse_spacing + start_and_end_clocks[0]));
			dummy_i += out_window;
			//Increment i if chan_1 < chan_2
			dummy_i += !out_window && (photon_bins[offset[channel_1 + shot_file_num * max_channels] + i] < (photon_bins[offset[channel_2 + shot_file_num * max_channels] + j] - tau));
			//Increment j if chan_1 > chan_2
			dummy_j += !out_window && (photon_bins[offset[channel_1 + shot_file_num * max_channels] + i] > (photon_bins[offset[channel_2 + shot_file_num * max_channels] + j] - tau));
			//If we have a common element increment the running_total and increment both i and j
			dummy_i += !out_window && (photon_bins[offset[channel_1 + shot_file_num * max_channels] + i] == (photon_bins[offset[channel_2 + shot_file_num * max_channels] + j] - tau));
			dummy_j += !out_window && (photon_bins[offset[channel_1 + shot_file_num * max_channels] + i] == (photon_bins[offset[channel_2 + shot_file_num * max_channels] + j] - tau));
			running_tot += !out_window && photon_bins[offset[channel_1 + shot_file_num * max_channels] + i] == (photon_bins[offset[channel_2 + shot_file_num * max_channels] + j] - tau);
			//running_tot += in_window;
			i += dummy_i;
			j += dummy_j;
		}
		coinc[block * block_size + id + shot_file_num * ((*max_bin * 2 + 1) + (*max_pulse_distance * 2))] += running_tot;
	}
}

__global__ void calculateCoincidencesGPU_g3(long int *coinc, long int *photon_bins, long int *start_and_end_clocks, int *max_bin, int *pulse_spacing, int *max_pulse_distance, int *offset, int *photon_bins_length, int num_channels, int shot_file_num) {
	//Get numerator step to work on
	int id = threadIdx.x;
	int block = blockIdx.x;
	int block_size = blockDim.x;

	//Check if the id is something we're going to do a calculation on
	int in_range = (block * block_size + id) < ((*max_bin * 2 + 1) * (*max_bin * 2 + 1) + (*max_pulse_distance * 2) * (*max_pulse_distance * 2));

	//Check if we're doing a denominator calculation
	int pulse_shift_measurement = in_range && (block * block_size + id >= (*max_bin * 2 + 1) * (*max_bin * 2 + 1));

	//Determine effective id for x and y
	int id_x = ((block * block_size + id) % (2 * (*max_bin) + 1)) * (!pulse_shift_measurement);
	id_x += ((block * block_size + id - (2 * (*max_bin) + 1) * (2 * (*max_bin) + 1)) % (2 * (*max_pulse_distance))) * (pulse_shift_measurement);
	int id_y = ((block * block_size + id) / (2 * (*max_bin) + 1)) * (!pulse_shift_measurement);
	id_y += ((block * block_size + id - (2 * (*max_bin) + 1) * (2 * (*max_bin) + 1)) / (2 * (*max_pulse_distance))) * (pulse_shift_measurement);

	//Check we're not calculating something out of range
	if (in_range && (!pulse_shift_measurement || (pulse_shift_measurement && id_x != id_y))) {

		int tau_1 = (id_x - (*max_bin)) * (!pulse_shift_measurement);
		int pulse_shift_1 = ((id_x - (*max_pulse_distance)) + ((id_x - (*max_pulse_distance)) >= 0)) * (pulse_shift_measurement);
		int pulse_shift_2 = ((id_y - (*max_pulse_distance)) + ((id_y - (*max_pulse_distance)) >= 0)) * (pulse_shift_measurement);
		tau_1 += pulse_shift_1 * (*pulse_spacing);
		int tau_2 = (id_y - (*max_bin)) * (!pulse_shift_measurement);
		tau_2 += pulse_shift_2 * (*pulse_spacing);
		for (int channel_1 = 0; channel_1 < num_channels; channel_1++) {
			for (int channel_2 = channel_1 + 1; channel_2 < num_channels; channel_2++) {
				for (int channel_3 = channel_2 + 1; channel_3 < num_channels; channel_3++) {
					int i = 0;
					int j = 0;
					int k = 0;
					int running_tot = 0;
					while ((i < photon_bins_length[channel_1 + shot_file_num * max_channels]) && (j < photon_bins_length[channel_2 + shot_file_num * max_channels]) && (k < photon_bins_length[channel_3 + shot_file_num * max_channels])) {
						int dummy_i = 0;
						int dummy_j = 0;
						int dummy_k = 0;

						int out_window = (photon_bins[offset[channel_1 + shot_file_num * max_channels] + i] < (*max_bin + *max_pulse_distance * *pulse_spacing + start_and_end_clocks[0 + shot_file_num * 2])) || (photon_bins[offset[channel_1 + shot_file_num * max_channels] + i] > (start_and_end_clocks[1 + shot_file_num * 2] - (*max_bin + *max_pulse_distance * *pulse_spacing)));
						//Chan_1 > chan_2
						int c1_g_c2 = !out_window && (photon_bins[offset[channel_1 + shot_file_num * max_channels] + i] >(photon_bins[offset[channel_2 + shot_file_num * max_channels] + j] - tau_1));
						//Chan_1 > chan_3
						int c1_g_c3 = !out_window && (photon_bins[offset[channel_1 + shot_file_num * max_channels] + i] >(photon_bins[offset[channel_3 + shot_file_num * max_channels] + k] - tau_2));
						////Chan_1 < chan_2
						//int c1_l_c2 = !out_window && (photon_bins[offset[channel_1 + shot_file_num * max_channels] + i] < (photon_bins[offset[channel_2 + shot_file_num * max_channels] + j] - tau_1));
						////Chan_1 < chan_3
						//int c1_l_c3 = !out_window && (photon_bins[offset[channel_1 + shot_file_num * max_channels] + i] > (photon_bins[offset[channel_3 + shot_file_num * max_channels] + k] - tau_2));
						//Chan_1 == chan_2
						int c1_e_c2 = !out_window && (photon_bins[offset[channel_1 + shot_file_num * max_channels] + i] == (photon_bins[offset[channel_2 + shot_file_num * max_channels] + j] - tau_1));
						//Chan_1 == chan_3
						int c1_e_c3 = !out_window && (photon_bins[offset[channel_1 + shot_file_num * max_channels] + i] == (photon_bins[offset[channel_3 + shot_file_num * max_channels] + k] - tau_2));

						//Increment i if we're outside the window of interest
						dummy_i = out_window;

						//Start by using chan_1 as a reference for chan_2 and chan_3 to get them to catch up
						//Increment j if chan_2 < chan_1
						dummy_j += !out_window && c1_g_c2;
						//Increment k if chan_3 < chan_1
						dummy_k += !out_window && c1_g_c3;

						//Now need to deal with situation where chan_1 !> chan_2 && chan_1 !> chan_3
						//First the easy situation where chan_1 == chan_2 == chan_3
						running_tot += !out_window && c1_e_c2 && c1_e_c3;
						dummy_i += !out_window && c1_e_c2 && c1_e_c3;
						dummy_j += !out_window && c1_e_c2 && c1_e_c3;
						dummy_k += !out_window && c1_e_c2 && c1_e_c3;

						//If we haven't incremented dummy_j or dummy_k then by process of elimination dummy_i needs to incremented
						dummy_i += !out_window && !dummy_j && !dummy_k;

						//running_tot += in_window;
						i += dummy_i;
						j += dummy_j;
						k += dummy_k;
					}
					coinc[(block * block_size + id) + shot_file_num * ((*max_bin * 2 + 1) * (*max_bin * 2 + 1) + (*max_pulse_distance * 2) * (*max_pulse_distance * 2))] += running_tot;
					//coinc[(block * block_size + id) + shot_file_num * ((*max_bin * 2 + 1) * (*max_bin * 2 + 1) + (*max_pulse_distance * 2) * (*max_pulse_distance * 2))] = (block * block_size + id) + shot_file_num * ((*max_bin * 2 + 1) * (*max_bin * 2 + 1) + (*max_pulse_distance * 2) * (*max_pulse_distance * 2));
				}
			}
		}
	}
}

//Function grabs all tags and channel list from file
void fileToShotData(shotData *shot_data, char* filename) {
	//Open up file
	H5::H5File file(filename, H5F_ACC_RDONLY);
	//Open up "Tags" group
	H5::Group tag_group(file.openGroup("Tags"));
	//Find out how many tag sets there are, should be 4 if not something is fucky
	hsize_t numTagsSets = tag_group.getNumObjs();
	if (numTagsSets != 4) {
		printf("There should be 4 sets of Tags, found %i\n", numTagsSets);
		delete filename;
		exit;
	}
	//Read tags to shotData structure
	//First the clock tags
	H5::DataSet clock_dset(tag_group.openDataSet("ClockTags0"));
	H5::DataSpace clock_dspace = clock_dset.getSpace();
	hsize_t clock_length[1];
	clock_dspace.getSimpleExtentDims(clock_length, NULL);
	shot_data->clock_tags.resize(clock_length[0]);
	clock_dset.read(&(*shot_data).clock_tags[0u], H5::PredType::NATIVE_UINT64, clock_dspace);
	clock_dspace.close();
	clock_dset.close();
	//Then start tags
	H5::DataSet start_dset(tag_group.openDataSet("StartTag"));
	H5::DataSpace start_dspace = start_dset.getSpace();
	hsize_t start_length[1];
	start_dspace.getSimpleExtentDims(start_length, NULL);
	shot_data->start_tags.resize(start_length[0]);
	start_dset.read(&(*shot_data).start_tags[0u], H5::PredType::NATIVE_UINT64, start_dspace);
	start_dspace.close();
	start_dset.close();
	//Then end tags
	H5::DataSet end_dset(tag_group.openDataSet("EndTag"));
	H5::DataSpace end_dspace = end_dset.getSpace();
	hsize_t end_length[1];
	end_dspace.getSimpleExtentDims(end_length, NULL);
	shot_data->end_tags.resize(end_length[0]);
	end_dset.read(&(*shot_data).end_tags[0u], H5::PredType::NATIVE_UINT64, end_dspace);
	end_dspace.close();
	end_dset.close();
	//Finally photon tags
	H5::DataSet photon_dset(tag_group.openDataSet("TagWindow0"));
	H5::DataSpace photon_dspace = photon_dset.getSpace();
	hsize_t photon_length[1];
	photon_dspace.getSimpleExtentDims(photon_length, NULL);
	shot_data->photon_tags.resize(photon_length[0]);
	photon_dset.read(&(*shot_data).photon_tags[0u], H5::PredType::NATIVE_UINT64, photon_dspace);
	photon_dspace.close();
	photon_dset.close();
	//And close tags group
	tag_group.close();
	//Open up "Inform" group
	H5::Group inform_group(file.openGroup("Inform"));
	//Grab channel list
	H5::DataSet chan_dset(inform_group.openDataSet("ChannelList"));
	H5::DataSpace chan_dspace = chan_dset.getSpace();
	hsize_t chan_length[1];
	chan_dspace.getSimpleExtentDims(chan_length, NULL);
	shot_data->channel_list.resize(chan_length[0]);
	chan_dset.read(&(*shot_data).channel_list[0u], H5::PredType::NATIVE_UINT16, chan_dspace);
	chan_dspace.close();
	chan_dset.close();
	//Close Inform group
	inform_group.close();
	//Close file
	file.close();

	//Populate channel map
	for (short int i = 0; i < shot_data->channel_list.size(); i++) {
		shot_data->channel_map[shot_data->channel_list[i]] = i;
	}
}

//Reads relevant information for a block of files into shot_block
void populateBlock(std::vector<shotData> *shot_block, std::vector<char *> *filelist, int block_num, int num_devices, int block_size) {
	//Loop over the block size
	for (int i = 0; i < block_size * num_devices; i++) {
		//Default to assuming the block is corrupted
		(*shot_block)[i].file_load_completed = false;
		//Figure out the file id within the filelist
		int file_id = block_num * block_size * num_devices + i;
		//Check the file_id isn't out of range of the filelist
		if (file_id < filelist->size()) {
			//Try to load file to shot_block
			try {
				fileToShotData(&(*shot_block)[i], (*filelist)[file_id]);
				(*shot_block)[i].file_load_completed = true;
			}
			//Will catch if the file is corrupted, print corrupted filenames to command window
			catch (...) {
				printf("%s appears corrupted\n", (*filelist)[file_id]);
			}
		}
	}
}

//Process the time tags, assigning them to the correct channel, binning them appropriately and removing tags which do not fall in the clock mask
void sortTags(shotData *shot_data) {
	long int i;
	int high_count = 0;
	//Loop over all tags in clock_tags
	for (i = 0; i < shot_data->clock_tags.size(); i++) {
		//Check if clock tag is a high word
		if (shot_data->clock_tags[i] & 1) {
			//Up the high count
			high_count++;
		}
		else {
			//Determine whether it is the rising (start) or falling (end) slope
			int slope = ((shot_data->clock_tags[i] >> 28) & 1);
			//Put tag in appropriate clock tag vector and increment the pointer for said vector
			shot_data->sorted_clock_tags[slope][shot_data->sorted_clock_tag_pointers[slope]] = ((shot_data->clock_tags[i] >> 1) & 0x7FFFFFF) + (high_count << 27) - ((shot_data->start_tags[1] >> 1) & 0x7FFFFFF);
			shot_data->sorted_clock_tag_pointers[slope]++;
		}
	}
	high_count = 0;
	//Clock pointer
	int clock_pointer = 0;
	//Loop over all tags in photon_tags
	for (i = 0; i < shot_data->photon_tags.size(); i++) {
		//Check if photon tag is a high word
		if (shot_data->photon_tags[i] & 1) {
			//Up the high count
			high_count++;
		}
		else {
			//Figure out if it fits within the mask
			long long int time_tag = ((shot_data->photon_tags[i] >> 1) & 0x7FFFFFF) + (high_count << 27) - ((shot_data->start_tags[1] >> 1) & 0x7FFFFFF);
			bool valid = true;
			while (valid) {
				//printf("%i\t%i\t%i\t", time_tag, shot_data->sorted_clock_tags[1][clock_pointer], shot_data->sorted_clock_tags[0][clock_pointer - 1]);
				//Increment dummy pointer if channel tag is greater than current start tag
				if ((time_tag >= shot_data->sorted_clock_tags[1][clock_pointer]) & (clock_pointer < shot_data->sorted_clock_tag_pointers[1])) {
					//printf("up clock pointer\n");
					clock_pointer++;
				}
				//Make sure clock_pointer is greater than 0, preventing an underflow error
				else if (clock_pointer > 0) {
					//Check if tag is lower than previous end tag i.e. startTags[j-1] < channeltags[i] < endTags[j-1]
					if (time_tag <= shot_data->sorted_clock_tags[0][clock_pointer - 1]) {
						//printf("add tag tot data\n");
						//Determine the index for given tag
						int channel_index;
						//Bin tag and assign to appropriate vector
						channel_index = shot_data->channel_map.find(((shot_data->photon_tags[i] >> 29) & 7) + 1)->second;
						shot_data->sorted_photon_tags[channel_index][shot_data->sorted_photon_tag_pointers[channel_index]] = time_tag;
						shot_data->sorted_photon_tag_pointers[channel_index]++;
						//printf("%i\t%i\t%i\n", channel_index, time_tag, shot_data->sorted_photon_tag_pointers[channel_index]);
					}
					//Break the valid loop
					valid = false;
				}
				// If tag is smaller than the first start tag
				else {
					valid = false;
				}
			}
		}
	}
}

//Converts our tags to bins with a given bin width
void tagsToBins(shotData *shot_data, double bin_width) {
	int tagger_bins_per_bin_width = (int)round(bin_width / tagger_resolution);
#pragma omp parallel for
	for (int channel = 0; channel < shot_data->sorted_photon_bins.size(); channel++) {
#pragma omp parallel for
		for (int i = 0; i < shot_data->sorted_photon_tag_pointers[channel]; i++) {
			shot_data->sorted_photon_bins[channel][i] = shot_data->sorted_photon_tags[channel][i] / tagger_bins_per_bin_width;
		}
	}
	for (int slope = 0; slope <= 1; slope++) {
#pragma omp parallel for
		for (int i = 0; i < shot_data->sorted_clock_tag_pointers[slope]; i++) {
			shot_data->sorted_clock_bins[slope][i] = shot_data->sorted_clock_tags[slope][i] / tagger_bins_per_bin_width;
		}
	}
}

//Sorts photons and bins them for each file in a block
void sortAndBinBlock(std::vector<shotData> *shot_block, double bin_width, int num_devices, int block_size) {
#pragma omp parallel for
	for (int shot_file_num = 0; shot_file_num < (block_size * num_devices); shot_file_num++) {
		if ((*shot_block)[shot_file_num].file_load_completed) {
			sortTags(&(*shot_block)[shot_file_num]);
			tagsToBins(&(*shot_block)[shot_file_num], bin_width);
		}
	}
}

void printShotChannelBins(shotData *shot_data, int channel) {
	for (int i = 0; i < shot_data->sorted_photon_tag_pointers[channel]; i++) {
		printf("%i\t%i\t%i\n", i, shot_data->sorted_photon_tags[channel][i], shot_data->sorted_photon_bins[channel][i]);
	}
}

DLLEXPORT void count_tags(char **file_list, int file_list_length, double max_time, double bin_width, double pulse_spacing, int max_pulse_distance) {
	std::vector<char *> filelist(file_list_length);
	//Grab filename and stick it into filelist vector
	for (int i = 0; i < file_list_length; i++) {
		filelist[i] = file_list[i];
	}

	int blocks_req;
	if (file_list_length< (file_block_size * 1)) {
		blocks_req = 1;
	}
	else if ((file_list_length % (file_block_size * 1)) == 0) {
		blocks_req = file_list_length / (file_block_size * 1);
	}
	else {
		blocks_req = file_list_length / (file_block_size * 1) + 1;
	}

	int max_bin = (int)round(max_time / bin_width);
	int bin_pulse_spacing = (int)round(pulse_spacing / bin_width);

	int num_tags_split[file_block_size][3] = { 0 };
	int num_tags_tot[3] = { 0 };

	printf("Max Time\tBin Width\tPulse Spacing\tMax Pulse Distance\n");
	printf("%fus\t%fns\t%fus\t%i\n", max_time * 1e6, bin_width * 1e9, pulse_spacing * 1e6, max_pulse_distance);

	//Processes files in blocks
	for (int block_num = 0; block_num < blocks_req; block_num++) {
		//Allocate a vector to hold a block of shot_data
		std::vector<shotData> shot_block(file_block_size * 1);

		//Populate the shot_block with data from file
		populateBlock(&shot_block, &filelist, block_num, 1, file_block_size);

		//Sort tags and convert them to bins
		sortAndBinBlock(&shot_block, bin_width, 1, file_block_size);

		for (int shot_file_num = 0; shot_file_num < file_block_size; shot_file_num++) {
			if ((shot_block)[shot_file_num].file_load_completed) {
				for (int channel = 0; channel < 3; channel++) {
					num_tags_tot[channel] += shot_block[shot_file_num].sorted_photon_tag_pointers[channel];
				}
			}
		}

		#pragma omp parallel for
		for (int shot_file_num = 0; shot_file_num < file_block_size; shot_file_num++) {
			if ((shot_block)[shot_file_num].file_load_completed) {
				int shot_num_tags[3] = { 0 };
				//printf("%f,%f\n", (shot_block[shot_file_num].sorted_clock_bins[1][0] + max_bin + bin_pulse_spacing * max_pulse_distance) * bin_width, (shot_block[shot_file_num].sorted_clock_bins[0][0] - max_bin - bin_pulse_spacing * max_pulse_distance) * bin_width);
				#pragma omp parallel for
				for (int channel = 0; channel < 3; channel++) {
					for (int i = 0; i < shot_block[shot_file_num].sorted_photon_tag_pointers[channel]; i++) {
						shot_num_tags[channel] += (shot_block[shot_file_num].sorted_photon_bins[channel][i] > shot_block[shot_file_num].sorted_clock_bins[1][0] + max_bin + bin_pulse_spacing * max_pulse_distance) && (shot_block[shot_file_num].sorted_photon_bins[channel][i] < shot_block[shot_file_num].sorted_clock_bins[0][0] - max_bin - bin_pulse_spacing * max_pulse_distance);
					}
					num_tags_split[shot_file_num][channel] += shot_num_tags[channel];
				}
			}
		}
	}
	int num_tags[3] = { 0 };
	for (int shot_file_num = 0; shot_file_num < file_block_size; shot_file_num++) {
		for (int channel = 0; channel < 3; channel++) {
			num_tags[channel] += num_tags_split[shot_file_num][channel];
		}
	}
	for (int channel = 0; channel < 3; channel++) {
		printf("Channel %i has %i out of %i tags in window\n", channel, num_tags[channel], num_tags_tot[channel]);
	}
}

DLLEXPORT void getG2Correlations_channelPair(char **file_list, int file_list_length, double max_time, double bin_width, double pulse_spacing, int max_pulse_distance, PyObject *numer, long int *denom, int channel_1, int channel_2) {

	std::vector<char *> filelist(file_list_length);
	//Grab filename and stick it into filelist vector
	for (int i = 0; i < file_list_length; i++) {
		filelist[i] = file_list[i];
	}

	int blocks_req;
	if (file_list_length< (file_block_size * num_gpu)) {
		blocks_req = 1;
	}
	else if ((file_list_length % (file_block_size * num_gpu)) == 0) {
		blocks_req = file_list_length / (file_block_size * num_gpu);
	}
	else {
		blocks_req = file_list_length / (file_block_size * num_gpu) + 1;
	}
	printf("Chunking %i files into %i blocks\n", file_list_length, blocks_req);
	printf("Max Time\tBin Width\tPulse Spacing\tMax Pulse Distance\n");
	printf("%fus\t%fns\t%fus\t%i\n", max_time * 1e6, bin_width * 1e9, pulse_spacing * 1e6, max_pulse_distance);

	int max_bin = (int)round(max_time / bin_width);
	int bin_pulse_spacing = (int)round(pulse_spacing / bin_width);

	//Figure out how many blocks to chunk the processing up into
	//For the numerator
	int cuda_blocks_numer = 0;
	if (threads_per_cuda_block_numer >= (max_bin * 2 + 1) + (max_pulse_distance * 2)) {
		cuda_blocks_numer = 1;
	}
	else if (((max_bin * 2 + 1) % threads_per_cuda_block_numer) == 0) {
		cuda_blocks_numer = ((max_bin * 2 + 1) + (max_pulse_distance * 2)) / threads_per_cuda_block_numer;
	}
	else {
		cuda_blocks_numer = ((max_bin * 2 + 1) + (max_pulse_distance * 2)) / threads_per_cuda_block_numer + 1;
	}

	cudaError_t cudaStatus;

	//Pointers for our various pinned memory for host-GPU DMA
	long int* pinned_photon_bins[num_gpu];
	long int* pinned_start_and_end_clocks[num_gpu];
	int* pinned_photon_bins_length[num_gpu];

	//Load some stuff to the GPU we will use permenantly
	//Allocate memory on GPU for various things
	gpuData gpu_data[num_gpu];

	for (int gpu = 0; gpu < num_gpu; gpu++) {

		cudaStatus = cudaSetDevice(gpu);
		if (cudaStatus != cudaSuccess) {
			printf("cudaSetDevice failed!  Do you have a CUDA-capable GPU installed?");
			goto Error;
		}

		cudaMallocHost((long int**)&pinned_photon_bins[gpu], max_tags_length * max_channels * file_block_size * sizeof(long int));
		cudaMallocHost((long int**)&pinned_start_and_end_clocks[gpu], 2 * file_block_size * sizeof(long int));
		cudaMallocHost((int**)&pinned_photon_bins_length[gpu], max_channels * file_block_size * sizeof(int));

		cudaStatus = cudaMalloc((void**)&((gpu_data[gpu]).photon_bins_gpu), max_channels * max_tags_length * file_block_size * sizeof(long int));
		if (cudaStatus != cudaSuccess) {
			printf("cudaMalloc photon_bins_gpu failed\n");
			printf("%s\n", cudaGetErrorString(cudaStatus));
			goto Error;
		}
		cudaStatus = cudaMalloc((void**)&((gpu_data[gpu]).offset_gpu), max_channels * file_block_size * sizeof(int));
		if (cudaStatus != cudaSuccess) {
			printf("cudaMalloc offset_gpu failed!\n");
			goto Error;
		}
		cudaStatus = cudaMalloc((void**)&((gpu_data[gpu]).photon_bins_length_gpu), max_channels * file_block_size * sizeof(int));
		if (cudaStatus != cudaSuccess) {
			printf("cudaMalloc photon_bins_length_gpu failed!\n");
			goto Error;
		}
		cudaStatus = cudaMalloc((void**)&((gpu_data[gpu]).coinc_gpu), ((2 * (max_bin)+1) + (max_pulse_distance * 2)) * file_block_size * sizeof(long int));
		if (cudaStatus != cudaSuccess) {
			printf("cudaMalloc numer_gpu failed!\n");
			goto Error;
		}
		cudaStatus = cudaMalloc((void**)&((gpu_data[gpu]).start_and_end_clocks_gpu), 2 * file_block_size * sizeof(long int));
		if (cudaStatus != cudaSuccess) {
			printf("cudaMalloc start_and_end_clocks_gpu failed!\n");
			goto Error;
		}
		cudaStatus = cudaMalloc((void**)&((gpu_data[gpu]).max_bin_gpu), sizeof(int));
		if (cudaStatus != cudaSuccess) {
			printf("cudaMalloc max_bin_gpu failed!\n");
			goto Error;
		}
		cudaStatus = cudaMalloc((void**)&((gpu_data[gpu]).pulse_spacing_gpu), sizeof(int));
		if (cudaStatus != cudaSuccess) {
			printf("cudaMalloc pulse_spacing_gpu failed!\n");
			goto Error;
		}
		cudaStatus = cudaMalloc((void**)&((gpu_data[gpu]).max_pulse_distance_gpu), sizeof(int));
		if (cudaStatus != cudaSuccess) {
			printf("cudaMalloc max_pulse_distance_gpu failed!\n");
			goto Error;
		}

		//And set some values that are constant across all data
		cudaStatus = cudaMemcpy(((gpu_data[gpu]).max_bin_gpu), &max_bin, sizeof(int), cudaMemcpyHostToDevice);
		if (cudaStatus != cudaSuccess) {
			printf("cudaMemcpy failed!\n");
			goto Error;
		}
		cudaStatus = cudaMemcpy(((gpu_data[gpu]).pulse_spacing_gpu), &bin_pulse_spacing, sizeof(int), cudaMemcpyHostToDevice);
		if (cudaStatus != cudaSuccess) {
			printf("cudaMemcpy failed!\n");
			goto Error;
		}
		cudaStatus = cudaMemcpy(((gpu_data[gpu]).max_pulse_distance_gpu), &max_pulse_distance, sizeof(int), cudaMemcpyHostToDevice);
		if (cudaStatus != cudaSuccess) {
			printf("cudaMemcpy failed!\n");
			goto Error;
		}

		//Pointer to first photon bin for each channel
		int host_offest_array[max_channels * file_block_size];
		for (int i = 0; i < max_channels * file_block_size; i++) {
			host_offest_array[i] = i * max_tags_length;
		}
		cudaStatus = cudaMemcpy(((gpu_data[gpu]).offset_gpu), host_offest_array, max_channels * file_block_size * sizeof(int), cudaMemcpyHostToDevice);
		if (cudaStatus != cudaSuccess) {
			printf("cudaMemcpy failed!\n");
			goto Error;
		}

		//Set numerator and denominator to 0
		cudaStatus = cudaMemset(((gpu_data[gpu])).coinc_gpu, 0, ((2 * (max_bin)+1) + (max_pulse_distance * 2)) * file_block_size * sizeof(long int));
		if (cudaStatus != cudaSuccess) {
			printf("cudaMemset failed!\n");
			goto Error;
		}
	}

	//Create some streams for us to use for GPU parallelism
	cudaStream_t streams[num_gpu][file_block_size];
	for (int gpu = 0; gpu < num_gpu; gpu++) {
		cudaStatus = cudaSetDevice(gpu);
		if (cudaStatus != cudaSuccess) {
			printf("cudaSetDevice failed!  Do you have a CUDA-capable GPU installed?");
			goto Error;
		}
		for (int i = 0; i < file_block_size; i++) {
			cudaStatus = cudaStreamCreate(&streams[gpu][i]);
			if (cudaStatus != cudaSuccess) {
				printf("Failed to create streams %s\n", cudaGetErrorString(cudaStatus));
				goto Error;
			}
		}
	}

	//Create some events to allow us to know if previous transfer has completed
	cudaEvent_t events[num_gpu][file_block_size];
	for (int gpu = 0; gpu < num_gpu; gpu++) {
		cudaStatus = cudaSetDevice(gpu);
		if (cudaStatus != cudaSuccess) {
			printf("cudaSetDevice failed!  Do you have a CUDA-capable GPU installed?");
			goto Error;
		}
		for (int i = 0; i < file_block_size; i++) {
			cudaEventCreate(&events[gpu][i]);
			if (cudaStatus != cudaSuccess) {
				printf("Failed to create events %s\n", cudaGetErrorString(cudaStatus));
				goto Error;
			}
		}
	}

	//Processes files in blocks
	for (int block_num = 0; block_num < blocks_req; block_num++) {
		//Allocate a vector to hold a block of shot_data
		std::vector<shotData> shot_block(file_block_size * num_gpu);

		//Populate the shot_block with data from file
		populateBlock(&shot_block, &filelist, block_num, num_gpu, file_block_size);

		//Sort tags and convert them to bins
		sortAndBinBlock(&shot_block, bin_width, num_gpu, file_block_size);
		//printShotChannelBins(&(shot_block[0]), 1);

		// cudaDeviceSynchronize waits for the kernel to finish, and returns
		// any errors encountered during the launch.
		/*cudaStatus = cudaDeviceSynchronize();
		if (cudaStatus != cudaSuccess) {
		printf("cudaDeviceSynchronize returned error code %d after launching addKernel!\n", cudaStatus);
		goto Error;
		}*/
		for (int gpu = 0; gpu < num_gpu; gpu++) {
			cudaStatus = cudaSetDevice(gpu);
			if (cudaStatus != cudaSuccess) {
				printf("cudaSetDevice failed!  Do you have a CUDA-capable GPU installed?");
				goto Error;
			}

			// Check for any errors launching the kernel
			cudaStatus = cudaGetLastError();
			if (cudaStatus != cudaSuccess) {
				printf("addKernel launch failed: %s\n", cudaGetErrorString(cudaStatus));
				goto Error;
			}

			//Asyncronously load data to GPU
			for (int shot_file_num = 0; shot_file_num < file_block_size; shot_file_num++) {
				int block_file_num = shot_file_num * num_gpu + gpu;
				if ((shot_block)[block_file_num].file_load_completed) {
					int num_channels = (shot_block)[block_file_num].channel_list.size();
					if (num_channels >= 2) {


						std::vector<long int*> photon_bins;
						long int start_and_end_clocks[2];
						std::vector<int> photon_bins_length;
						photon_bins.resize(max_channels);
						photon_bins_length.resize(max_channels);

						start_and_end_clocks[0] = (shot_block)[block_file_num].sorted_clock_bins[1][0];
						start_and_end_clocks[1] = (shot_block)[block_file_num].sorted_clock_bins[0][0];
						for (int i = 0; i < num_channels; i++) {
							photon_bins[i] = &((shot_block)[block_file_num].sorted_photon_bins[i][0]);
							photon_bins_length[i] = (shot_block)[block_file_num].sorted_photon_tag_pointers[i];
						}

						//Synch to ensure previous asnyc memcopy has finished otherwise we'll start overwriting writing to data that may be DMA'd
						cudaStatus = cudaEventSynchronize(events[gpu][shot_file_num]);
						if (cudaStatus != cudaSuccess) {
							printf("Event synch failed\n");
							goto Error;
						}

						//Write photon bins to memory
						int photon_offset = shot_file_num * max_channels * max_tags_length;
						for (int i = 0; i < photon_bins_length.size(); i++) {
							memcpy(pinned_photon_bins[gpu] + photon_offset, (photon_bins)[i], (photon_bins_length)[i] * sizeof(long int));
							cudaStatus = cudaMemcpyAsync((gpu_data[gpu]).photon_bins_gpu + photon_offset, pinned_photon_bins[gpu] + photon_offset, (photon_bins_length)[i] * sizeof(long int), cudaMemcpyHostToDevice, streams[gpu][shot_file_num]);
							if (cudaStatus != cudaSuccess) {
								printf("cudaMemcpy photon_bins failed!\n");
								goto Error;
							}
							photon_offset += max_tags_length;
						}

						int clock_offset = shot_file_num * 2;
						//And other parameters
						memcpy(pinned_start_and_end_clocks[gpu] + clock_offset, start_and_end_clocks, 2 * sizeof(long int));
						cudaStatus = cudaMemcpyAsync((gpu_data[gpu]).start_and_end_clocks_gpu + clock_offset, pinned_start_and_end_clocks[gpu] + clock_offset, 2 * sizeof(long int), cudaMemcpyHostToDevice, streams[gpu][shot_file_num]);
						if (cudaStatus != cudaSuccess) {
							printf("cudaMemcpy clock_offset failed!\n");
							goto Error;
						}

						int length_offset = shot_file_num * max_channels;
						//Can't copy vector to cuda easily
						for (int i = 0; i < photon_bins_length.size(); i++) {
							memcpy(pinned_photon_bins_length[gpu] + i + length_offset, &((photon_bins_length)[i]), sizeof(int));
						}
						cudaStatus = cudaMemcpyAsync((gpu_data[gpu]).photon_bins_length_gpu + length_offset, pinned_photon_bins_length[gpu] + length_offset, max_channels * sizeof(int), cudaMemcpyHostToDevice, streams[gpu][shot_file_num]);
						if (cudaStatus != cudaSuccess) {
							printf("cudaMemcpy length_offset failed!\n");
							goto Error;
						}

						//Create an event to let us know all the async copies have occured
						cudaEventRecord(events[gpu][shot_file_num], streams[gpu][shot_file_num]);
						//Run kernels
						calculateCoincidencesGPU_g2_channelPair<< <cuda_blocks_numer, threads_per_cuda_block_numer, 0, streams[gpu][shot_file_num] >> > ((gpu_data[gpu]).coinc_gpu, (gpu_data[gpu]).photon_bins_gpu, (gpu_data[gpu]).start_and_end_clocks_gpu, (gpu_data[gpu]).max_bin_gpu, (gpu_data[gpu]).pulse_spacing_gpu, (gpu_data[gpu]).max_pulse_distance_gpu, (gpu_data[gpu]).offset_gpu, (gpu_data[gpu]).photon_bins_length_gpu, channel_1, channel_2, shot_file_num);
					}
				}
			}
		}
		printf("Sent block %i/%i\n", block_num + 1, blocks_req);
	}
	printf("Finished sending blocks\n");

	for (int gpu = 0; gpu < num_gpu; gpu++) {
		cudaStatus = cudaSetDevice(gpu);
		if (cudaStatus != cudaSuccess) {
			printf("cudaSetDevice failed!  Do you have a CUDA-capable GPU installed?");
			goto Error;
		}
		for (int i = 0; i < file_block_size; i++) {
			cudaStatus = cudaStreamSynchronize(streams[gpu][i]);
			if (cudaStatus != cudaSuccess) {
				printf("cudaDeviceSynchronize returned error code %d after launching addKernel!\n", cudaStatus);
				goto Error;
			}
		}
	}

	//Free pinned memory
	for (int gpu = 0; gpu < num_gpu; gpu++) {
		cudaStatus = cudaSetDevice(gpu);
		if (cudaStatus != cudaSuccess) {
			printf("cudaSetDevice failed!  Do you have a CUDA-capable GPU installed?");
			goto Error;
		}
		cudaFreeHost(pinned_photon_bins[gpu]);
		cudaFreeHost(pinned_photon_bins_length[gpu]);
		cudaFreeHost(pinned_start_and_end_clocks[gpu]);
	}

	//This is to pull the streamed numerator off the GPU
	//Streamed numerator refers to the way the numerator is stored on the GPU where each GPU stream has a seperate numerator
	for (int gpu = 0; gpu < num_gpu; gpu++) {
		cudaStatus = cudaSetDevice(gpu);
		if (cudaStatus != cudaSuccess) {
			printf("cudaSetDevice failed!  Do you have a CUDA-capable GPU installed?");
			goto Error;
		}
		long int *streamed_coinc;
		streamed_coinc = (long int *)malloc(((2 * (max_bin)+1) + (max_pulse_distance * 2)) * file_block_size * sizeof(long int));

		// Copy output vector from GPU buffer to host memory.
		cudaStatus = cudaMemcpy(streamed_coinc, (gpu_data[gpu]).coinc_gpu, ((2 * (max_bin)+1) + (max_pulse_distance * 2)) * file_block_size * sizeof(long int), cudaMemcpyDeviceToHost);
		if (cudaStatus != cudaSuccess) {
			printf("cudaMemcpy numerator failed!\n");
			free(streamed_coinc);
			goto Error;
		}

		//Collapse streamed coincidence counts down to regular numerator and denominator
		for (int i = 0; i < file_block_size; i++) {
			for (int j = 0; j < ((2 * (max_bin)+1) + (max_pulse_distance * 2)); j++) {
				if (j < (2 * (max_bin)+1)) {
					PyList_SetItem(numer, j, PyLong_FromLong(PyLong_AsLong(PyList_GetItem(numer, j)) + streamed_coinc[j + i * ((2 * (max_bin)+1) + (max_pulse_distance * 2))]));
				}
				else {
					denom[0] += streamed_coinc[j + i * ((2 * (max_bin)+1) + (max_pulse_distance * 2))];
				}
			}
		}
		free(streamed_coinc);
	}

	//Release CUDA device
	for (int gpu = 0; gpu < num_gpu; gpu++) {
		cudaStatus = cudaSetDevice(gpu);
		if (cudaStatus != cudaSuccess) {
			printf("cudaSetDevice failed!  Do you have a CUDA-capable GPU installed?");
			goto Error;
		}
		cudaStatus = cudaDeviceReset();
		if (cudaStatus != cudaSuccess) {
			printf("cudaDeviceReset failed!\n");
		}
	}

Error:
	for (int gpu = 0; gpu < num_gpu; gpu++) {
		cudaStatus = cudaSetDevice(gpu);
		if (cudaStatus != cudaSuccess) {
			printf("cudaSetDevice failed!  Do you have a CUDA-capable GPU installed?");
			goto Error;
		}
		cudaFree((gpu_data[gpu].coinc_gpu));
		cudaFree((gpu_data[gpu].offset_gpu));
		cudaFree((gpu_data[gpu].max_bin_gpu));
		cudaFree((gpu_data[gpu].pulse_spacing_gpu));
		cudaFree((gpu_data[gpu].max_pulse_distance_gpu));
		cudaFree((gpu_data[gpu].photon_bins_length_gpu));
		cudaFree(gpu_data[gpu].photon_bins_gpu);
		cudaFree(gpu_data[gpu].start_and_end_clocks_gpu);
		cudaFreeHost(pinned_photon_bins[gpu]);
		cudaFreeHost(pinned_photon_bins_length[gpu]);
		cudaFreeHost(pinned_start_and_end_clocks[gpu]);
		cudaDeviceReset();
	}
}

DLLEXPORT void getG2Correlations(char **file_list, int file_list_length, double max_time, double bin_width, double pulse_spacing, int max_pulse_distance, PyObject *numer, long int *denom) {
	
	std::vector<char *> filelist(file_list_length);
	//Grab filename and stick it into filelist vector
	for (int i = 0; i < file_list_length; i++) {
		filelist[i] = file_list[i];
	}

	int blocks_req;
	if (file_list_length< (file_block_size * num_gpu)) {
		blocks_req = 1;
	}
	else if ((file_list_length % (file_block_size * num_gpu)) == 0) {
		blocks_req = file_list_length / (file_block_size * num_gpu);
	}
	else {
		blocks_req = file_list_length / (file_block_size * num_gpu) + 1;
	}
	printf("Chunking %i files into %i blocks\n", file_list_length, blocks_req);
	printf("Max Time\tBin Width\tPulse Spacing\tMax Pulse Distance\n");
	printf("%fus\t%fns\t%fus\t%i\n", max_time * 1e6, bin_width * 1e9, pulse_spacing * 1e6, max_pulse_distance);

	int max_bin = (int)round(max_time / bin_width);
	int bin_pulse_spacing = (int)round(pulse_spacing / bin_width);

	//Figure out how many blocks to chunk the processing up into
	//For the numerator
	int cuda_blocks_numer = 0;
	if (threads_per_cuda_block_numer >= (max_bin * 2 + 1) + (max_pulse_distance * 2)) {
		cuda_blocks_numer = 1;
	}
	else if (((max_bin * 2 + 1) % threads_per_cuda_block_numer) == 0) {
		cuda_blocks_numer = ((max_bin * 2 + 1) + (max_pulse_distance * 2)) / threads_per_cuda_block_numer;
	}
	else {
		cuda_blocks_numer = ((max_bin * 2 + 1) + (max_pulse_distance * 2)) / threads_per_cuda_block_numer + 1;
	}

	cudaError_t cudaStatus;

	//Pointers for our various pinned memory for host-GPU DMA
	long int* pinned_photon_bins[num_gpu];
	long int* pinned_start_and_end_clocks[num_gpu];
	int* pinned_photon_bins_length[num_gpu];

	//Load some stuff to the GPU we will use permenantly
	//Allocate memory on GPU for various things
	gpuData gpu_data[num_gpu];
	
	for (int gpu = 0; gpu < num_gpu; gpu++) {

		cudaStatus = cudaSetDevice(gpu);
		if (cudaStatus != cudaSuccess) {
			printf("cudaSetDevice failed!  Do you have a CUDA-capable GPU installed?");
			goto Error;
		}

		cudaMallocHost((long int**)&pinned_photon_bins[gpu], max_tags_length * max_channels * file_block_size * sizeof(long int));
		cudaMallocHost((long int**)&pinned_start_and_end_clocks[gpu], 2 * file_block_size * sizeof(long int));
		cudaMallocHost((int**)&pinned_photon_bins_length[gpu], max_channels * file_block_size * sizeof(int));

		cudaStatus = cudaMalloc((void**)&((gpu_data[gpu]).photon_bins_gpu), max_channels * max_tags_length * file_block_size * sizeof(long int));
		if (cudaStatus != cudaSuccess) {
			printf("cudaMalloc photon_bins_gpu failed\n");
			printf("%s\n", cudaGetErrorString(cudaStatus));
			goto Error;
		}
		cudaStatus = cudaMalloc((void**)&((gpu_data[gpu]).offset_gpu), max_channels * file_block_size * sizeof(int));
		if (cudaStatus != cudaSuccess) {
			printf("cudaMalloc offset_gpu failed!\n");
			goto Error;
		}
		cudaStatus = cudaMalloc((void**)&((gpu_data[gpu]).photon_bins_length_gpu), max_channels * file_block_size * sizeof(int));
		if (cudaStatus != cudaSuccess) {
			printf("cudaMalloc photon_bins_length_gpu failed!\n");
			goto Error;
		}
		cudaStatus = cudaMalloc((void**)&((gpu_data[gpu]).coinc_gpu), ((2 * (max_bin)+1) + (max_pulse_distance * 2)) * file_block_size * sizeof(long int));
		if (cudaStatus != cudaSuccess) {
			printf("cudaMalloc numer_gpu failed!\n");
			goto Error;
		}
		cudaStatus = cudaMalloc((void**)&((gpu_data[gpu]).start_and_end_clocks_gpu), 2 * file_block_size * sizeof(long int));
		if (cudaStatus != cudaSuccess) {
			printf("cudaMalloc start_and_end_clocks_gpu failed!\n");
			goto Error;
		}
		cudaStatus = cudaMalloc((void**)&((gpu_data[gpu]).max_bin_gpu), sizeof(int));
		if (cudaStatus != cudaSuccess) {
			printf("cudaMalloc max_bin_gpu failed!\n");
			goto Error;
		}
		cudaStatus = cudaMalloc((void**)&((gpu_data[gpu]).pulse_spacing_gpu), sizeof(int));
		if (cudaStatus != cudaSuccess) {
			printf("cudaMalloc pulse_spacing_gpu failed!\n");
			goto Error;
		}
		cudaStatus = cudaMalloc((void**)&((gpu_data[gpu]).max_pulse_distance_gpu), sizeof(int));
		if (cudaStatus != cudaSuccess) {
			printf("cudaMalloc max_pulse_distance_gpu failed!\n");
			goto Error;
		}

		//And set some values that are constant across all data
		cudaStatus = cudaMemcpy(((gpu_data[gpu]).max_bin_gpu), &max_bin, sizeof(int), cudaMemcpyHostToDevice);
		if (cudaStatus != cudaSuccess) {
			printf("cudaMemcpy failed!\n");
			goto Error;
		}
		cudaStatus = cudaMemcpy(((gpu_data[gpu]).pulse_spacing_gpu), &bin_pulse_spacing, sizeof(int), cudaMemcpyHostToDevice);
		if (cudaStatus != cudaSuccess) {
			printf("cudaMemcpy failed!\n");
			goto Error;
		}
		cudaStatus = cudaMemcpy(((gpu_data[gpu]).max_pulse_distance_gpu), &max_pulse_distance, sizeof(int), cudaMemcpyHostToDevice);
		if (cudaStatus != cudaSuccess) {
			printf("cudaMemcpy failed!\n");
			goto Error;
		}

		//Pointer to first photon bin for each channel
		int host_offest_array[max_channels * file_block_size];
		for (int i = 0; i < max_channels * file_block_size; i++) {
			host_offest_array[i] = i * max_tags_length;
		}
		cudaStatus = cudaMemcpy(((gpu_data[gpu]).offset_gpu), host_offest_array, max_channels * file_block_size * sizeof(int), cudaMemcpyHostToDevice);
		if (cudaStatus != cudaSuccess) {
			printf("cudaMemcpy failed!\n");
			goto Error;
		}

		//Set numerator and denominator to 0
		cudaStatus = cudaMemset(((gpu_data[gpu])).coinc_gpu, 0, ((2 * (max_bin)+1) + (max_pulse_distance * 2)) * file_block_size * sizeof(long int));
		if (cudaStatus != cudaSuccess) {
			printf("cudaMemset failed!\n");
			goto Error;
		}
	}

	//Create some streams for us to use for GPU parallelism
	cudaStream_t streams[num_gpu][file_block_size];
	for (int gpu = 0; gpu < num_gpu; gpu++) {
		cudaStatus = cudaSetDevice(gpu);
		if (cudaStatus != cudaSuccess) {
			printf("cudaSetDevice failed!  Do you have a CUDA-capable GPU installed?");
			goto Error;
		}
		for (int i = 0; i < file_block_size; i++) {
			cudaStatus = cudaStreamCreate(&streams[gpu][i]);
			if (cudaStatus != cudaSuccess) {
				printf("Failed to create streams %s\n", cudaGetErrorString(cudaStatus));
				goto Error;
			}
		}
	}

	//Create some events to allow us to know if previous transfer has completed
	cudaEvent_t events[num_gpu][file_block_size];
	for (int gpu = 0; gpu < num_gpu; gpu++) {
		cudaStatus = cudaSetDevice(gpu);
		if (cudaStatus != cudaSuccess) {
			printf("cudaSetDevice failed!  Do you have a CUDA-capable GPU installed?");
			goto Error;
		}
		for (int i = 0; i < file_block_size; i++) {
			cudaEventCreate(&events[gpu][i]);
			if (cudaStatus != cudaSuccess) {
				printf("Failed to create events %s\n", cudaGetErrorString(cudaStatus));
				goto Error;
			}
		}
	}

	//Processes files in blocks
	for (int block_num = 0; block_num < blocks_req; block_num++) {
		//Allocate a vector to hold a block of shot_data
		std::vector<shotData> shot_block(file_block_size * num_gpu);

		//Populate the shot_block with data from file
		populateBlock(&shot_block, &filelist, block_num, num_gpu, file_block_size);

		//Sort tags and convert them to bins
		sortAndBinBlock(&shot_block, bin_width, num_gpu, file_block_size);
		//printShotChannelBins(&(shot_block[0]), 1);

		// cudaDeviceSynchronize waits for the kernel to finish, and returns
		// any errors encountered during the launch.
		/*cudaStatus = cudaDeviceSynchronize();
		if (cudaStatus != cudaSuccess) {
		printf("cudaDeviceSynchronize returned error code %d after launching addKernel!\n", cudaStatus);
		goto Error;
		}*/
		for (int gpu = 0; gpu < num_gpu; gpu++) {
			cudaStatus = cudaSetDevice(gpu);
			if (cudaStatus != cudaSuccess) {
				printf("cudaSetDevice failed!  Do you have a CUDA-capable GPU installed?");
				goto Error;
			}

			// Check for any errors launching the kernel
			cudaStatus = cudaGetLastError();
			if (cudaStatus != cudaSuccess) {
				printf("addKernel launch failed: %s\n", cudaGetErrorString(cudaStatus));
				goto Error;
			}

			//Asyncronously load data to GPU
			for (int shot_file_num = 0; shot_file_num < file_block_size; shot_file_num++) {
				int block_file_num = shot_file_num * num_gpu + gpu;
				if ((shot_block)[block_file_num].file_load_completed) {
					int num_channels = (shot_block)[block_file_num].channel_list.size();
					if (num_channels >= 2) {


						std::vector<long int*> photon_bins;
						long int start_and_end_clocks[2];
						std::vector<int> photon_bins_length;
						photon_bins.resize(max_channels);
						photon_bins_length.resize(max_channels);

						start_and_end_clocks[0] = (shot_block)[block_file_num].sorted_clock_bins[1][0];
						start_and_end_clocks[1] = (shot_block)[block_file_num].sorted_clock_bins[0][0];
						for (int i = 0; i < num_channels; i++) {
							photon_bins[i] = &((shot_block)[block_file_num].sorted_photon_bins[i][0]);
							photon_bins_length[i] = (shot_block)[block_file_num].sorted_photon_tag_pointers[i];
						}

						//Synch to ensure previous asnyc memcopy has finished otherwise we'll start overwriting writing to data that may be DMA'd
						cudaStatus = cudaEventSynchronize(events[gpu][shot_file_num]);
						if (cudaStatus != cudaSuccess) {
							printf("Event synch failed\n");
							goto Error;
						}

						//Write photon bins to memory
						int photon_offset = shot_file_num * max_channels * max_tags_length;
						for (int i = 0; i < photon_bins_length.size(); i++) {
							memcpy(pinned_photon_bins[gpu] + photon_offset, (photon_bins)[i], (photon_bins_length)[i] * sizeof(long int));
							cudaStatus = cudaMemcpyAsync((gpu_data[gpu]).photon_bins_gpu + photon_offset, pinned_photon_bins[gpu] + photon_offset, (photon_bins_length)[i] * sizeof(long int), cudaMemcpyHostToDevice, streams[gpu][shot_file_num]);
							if (cudaStatus != cudaSuccess) {
								printf("cudaMemcpy photon_bins failed!\n");
								goto Error;
							}
							photon_offset += max_tags_length;
						}

						int clock_offset = shot_file_num * 2;
						//And other parameters
						memcpy(pinned_start_and_end_clocks[gpu] + clock_offset, start_and_end_clocks, 2 * sizeof(long int));
						cudaStatus = cudaMemcpyAsync((gpu_data[gpu]).start_and_end_clocks_gpu + clock_offset, pinned_start_and_end_clocks[gpu] + clock_offset, 2 * sizeof(long int), cudaMemcpyHostToDevice, streams[gpu][shot_file_num]);
						if (cudaStatus != cudaSuccess) {
							printf("cudaMemcpy clock_offset failed!\n");
							goto Error;
						}

						int length_offset = shot_file_num * max_channels;
						//Can't copy vector to cuda easily
						for (int i = 0; i < photon_bins_length.size(); i++) {
							memcpy(pinned_photon_bins_length[gpu] + i + length_offset, &((photon_bins_length)[i]), sizeof(int));
						}
						cudaStatus = cudaMemcpyAsync((gpu_data[gpu]).photon_bins_length_gpu + length_offset, pinned_photon_bins_length[gpu] + length_offset, max_channels * sizeof(int), cudaMemcpyHostToDevice, streams[gpu][shot_file_num]);
						if (cudaStatus != cudaSuccess) {
							printf("cudaMemcpy length_offset failed!\n");
							goto Error;
						}

						//Create an event to let us know all the async copies have occured
						cudaEventRecord(events[gpu][shot_file_num], streams[gpu][shot_file_num]);
						//Run kernels
						calculateCoincidencesGPU_g2_test << <cuda_blocks_numer, threads_per_cuda_block_numer, 0, streams[gpu][shot_file_num] >> > ((gpu_data[gpu]).coinc_gpu, (gpu_data[gpu]).photon_bins_gpu, (gpu_data[gpu]).start_and_end_clocks_gpu, (gpu_data[gpu]).max_bin_gpu, (gpu_data[gpu]).pulse_spacing_gpu, (gpu_data[gpu]).max_pulse_distance_gpu, (gpu_data[gpu]).offset_gpu, (gpu_data[gpu]).photon_bins_length_gpu, num_channels, shot_file_num);
					}
				}
			}
		}
		printf("Sent block %i/%i\n", block_num + 1, blocks_req);
	}
	printf("Finished sending blocks\n");

	for (int gpu = 0; gpu < num_gpu; gpu++) {
		cudaStatus = cudaSetDevice(gpu);
		if (cudaStatus != cudaSuccess) {
			printf("cudaSetDevice failed!  Do you have a CUDA-capable GPU installed?");
			goto Error;
		}
		for (int i = 0; i < file_block_size; i++) {
			cudaStatus = cudaStreamSynchronize(streams[gpu][i]);
			if (cudaStatus != cudaSuccess) {
				printf("cudaDeviceSynchronize returned error code %d after launching addKernel!\n", cudaStatus);
				goto Error;
			}
		}
	}

	//Free pinned memory
	for (int gpu = 0; gpu < num_gpu; gpu++) {
		cudaStatus = cudaSetDevice(gpu);
		if (cudaStatus != cudaSuccess) {
			printf("cudaSetDevice failed!  Do you have a CUDA-capable GPU installed?");
			goto Error;
		}
		cudaFreeHost(pinned_photon_bins[gpu]);
		cudaFreeHost(pinned_photon_bins_length[gpu]);
		cudaFreeHost(pinned_start_and_end_clocks[gpu]);
	}

	//This is to pull the streamed numerator off the GPU
	//Streamed numerator refers to the way the numerator is stored on the GPU where each GPU stream has a seperate numerator
	for (int gpu = 0; gpu < num_gpu; gpu++) {
		cudaStatus = cudaSetDevice(gpu);
		if (cudaStatus != cudaSuccess) {
			printf("cudaSetDevice failed!  Do you have a CUDA-capable GPU installed?");
			goto Error;
		}
		long int *streamed_coinc;
		streamed_coinc = (long int *)malloc(((2 * (max_bin)+1) + (max_pulse_distance * 2)) * file_block_size * sizeof(long int));

		// Copy output vector from GPU buffer to host memory.
		cudaStatus = cudaMemcpy(streamed_coinc, (gpu_data[gpu]).coinc_gpu, ((2 * (max_bin)+1) + (max_pulse_distance * 2)) * file_block_size * sizeof(long int), cudaMemcpyDeviceToHost);
		if (cudaStatus != cudaSuccess) {
			printf("cudaMemcpy numerator failed!\n");
			free(streamed_coinc);
			goto Error;
		}

		//Collapse streamed coincidence counts down to regular numerator and denominator
		for (int i = 0; i < file_block_size; i++) {
			for (int j = 0; j < ((2 * (max_bin)+1) + (max_pulse_distance * 2)); j++) {
				if (j < (2 * (max_bin)+1)) {
					PyList_SetItem(numer, j, PyLong_FromLong(PyLong_AsLong(PyList_GetItem(numer, j)) + streamed_coinc[j + i * ((2 * (max_bin)+1) + (max_pulse_distance * 2))]));
				}
				else {
					denom[0] += streamed_coinc[j + i * ((2 * (max_bin)+1) + (max_pulse_distance * 2))];
				}
			}
		}
		free(streamed_coinc);
	}

	//Release CUDA device
	for (int gpu = 0; gpu < num_gpu; gpu++) {
		cudaStatus = cudaSetDevice(gpu);
		if (cudaStatus != cudaSuccess) {
			printf("cudaSetDevice failed!  Do you have a CUDA-capable GPU installed?");
			goto Error;
		}
		cudaStatus = cudaDeviceReset();
		if (cudaStatus != cudaSuccess) {
			printf("cudaDeviceReset failed!\n");
		}
	}

Error:
	for (int gpu = 0; gpu < num_gpu; gpu++) {
		cudaStatus = cudaSetDevice(gpu);
		if (cudaStatus != cudaSuccess) {
			printf("cudaSetDevice failed!  Do you have a CUDA-capable GPU installed?");
			goto Error;
		}
		cudaFree((gpu_data[gpu].coinc_gpu));
		cudaFree((gpu_data[gpu].offset_gpu));
		cudaFree((gpu_data[gpu].max_bin_gpu));
		cudaFree((gpu_data[gpu].pulse_spacing_gpu));
		cudaFree((gpu_data[gpu].max_pulse_distance_gpu));
		cudaFree((gpu_data[gpu].photon_bins_length_gpu));
		cudaFree(gpu_data[gpu].photon_bins_gpu);
		cudaFree(gpu_data[gpu].start_and_end_clocks_gpu);
		cudaFreeHost(pinned_photon_bins[gpu]);
		cudaFreeHost(pinned_photon_bins_length[gpu]);
		cudaFreeHost(pinned_start_and_end_clocks[gpu]);
		cudaDeviceReset();
	}
}

DLLEXPORT void getG3Correlations(char **file_list, int file_list_length, double max_time, double bin_width, double pulse_spacing, int max_pulse_distance, PyObject *numer, long int *denom) {
	std::vector<char *> filelist(file_list_length);
	//Grab filename and stick it into filelist vector
	for (int i = 0; i < file_list_length; i++) {
		filelist[i] = file_list[i];
	}

	int blocks_req;
	if (file_list_length< (file_block_size * num_gpu)) {
		blocks_req = 1;
	}
	else if ((file_list_length % (file_block_size * num_gpu)) == 0) {
		blocks_req = file_list_length / (file_block_size * num_gpu);
	}
	else {
		blocks_req = file_list_length / (file_block_size * num_gpu) + 1;
	}
	printf("Chunking %i files into %i blocks\n", file_list_length, blocks_req);
	printf("Max Time\tBin Width\tPulse Spacing\tMax Pulse Distance\n");
	printf("%fus\t%fns\t%fus\t%i\n", max_time * 1e6, bin_width * 1e9, pulse_spacing * 1e6, max_pulse_distance);

	int max_bin = (int)round(max_time / bin_width);
	int bin_pulse_spacing = (int)round(pulse_spacing / bin_width);

	//Figure out how many blocks to chunk the processing up into
	//For the numerator
	int cuda_blocks_numer = 0;
	if (threads_per_cuda_block_numer >= ((2 * (max_bin)+1) * (2 * (max_bin)+1)) + (max_pulse_distance * 2) * (max_pulse_distance * 2)) {
		cuda_blocks_numer = 1;
	}
	else if (((max_bin * 2 + 1) % threads_per_cuda_block_numer) == 0) {
		cuda_blocks_numer = (((2 * (max_bin)+1) * (2 * (max_bin)+1)) + (max_pulse_distance * 2) * (max_pulse_distance * 2)) / threads_per_cuda_block_numer;
	}
	else {
		cuda_blocks_numer = (((2 * (max_bin)+1) * (2 * (max_bin)+1)) + (max_pulse_distance * 2) * (max_pulse_distance * 2)) / threads_per_cuda_block_numer + 1;
	}

	cudaError_t cudaStatus;

	//Pointers for our various pinned memory for host-GPU DMA
	long int* pinned_photon_bins[num_gpu];
	long int* pinned_start_and_end_clocks[num_gpu];
	int* pinned_photon_bins_length[num_gpu];

	//Load some stuff to the GPU we will use permenantly
	//Allocate memory on GPU for various things
	gpuData gpu_data[num_gpu];

	for (int gpu = 0; gpu < num_gpu; gpu++) {

		cudaStatus = cudaSetDevice(gpu);
		if (cudaStatus != cudaSuccess) {
			printf("cudaSetDevice failed!  Do you have a CUDA-capable GPU installed?");
			goto Error;
		}

		cudaMallocHost((long int**)&pinned_photon_bins[gpu], max_tags_length * max_channels * file_block_size * sizeof(long int));
		cudaMallocHost((long int**)&pinned_start_and_end_clocks[gpu], 2 * file_block_size * sizeof(long int));
		cudaMallocHost((int**)&pinned_photon_bins_length[gpu], max_channels * file_block_size * sizeof(int));

		cudaStatus = cudaMalloc((void**)&((gpu_data[gpu]).photon_bins_gpu), max_channels * max_tags_length * file_block_size * sizeof(long int));
		if (cudaStatus != cudaSuccess) {
			printf("cudaMalloc photon_bins_gpu failed\n");
			printf("%s\n", cudaGetErrorString(cudaStatus));
			goto Error;
		}
		cudaStatus = cudaMalloc((void**)&((gpu_data[gpu]).offset_gpu), max_channels * file_block_size * sizeof(int));
		if (cudaStatus != cudaSuccess) {
			printf("cudaMalloc offset_gpu failed!\n");
			goto Error;
		}
		cudaStatus = cudaMalloc((void**)&((gpu_data[gpu]).photon_bins_length_gpu), max_channels * file_block_size * sizeof(int));
		if (cudaStatus != cudaSuccess) {
			printf("cudaMalloc photon_bins_length_gpu failed!\n");
			goto Error;
		}
		cudaStatus = cudaMalloc((void**)&(gpu_data[gpu].coinc_gpu), (((2 * (max_bin)+1) * (2 * (max_bin)+1)) + (max_pulse_distance * 2) * (max_pulse_distance * 2)) * file_block_size * sizeof(long int));
		if (cudaStatus != cudaSuccess) {
			printf("cudaMalloc numer_gpu failed!\n");
			goto Error;
		}
		cudaStatus = cudaMalloc((void**)&((gpu_data[gpu]).start_and_end_clocks_gpu), 2 * file_block_size * sizeof(long int));
		if (cudaStatus != cudaSuccess) {
			printf("cudaMalloc start_and_end_clocks_gpu failed!\n");
			goto Error;
		}
		cudaStatus = cudaMalloc((void**)&((gpu_data[gpu]).max_bin_gpu), sizeof(int));
		if (cudaStatus != cudaSuccess) {
			printf("cudaMalloc max_bin_gpu failed!\n");
			goto Error;
		}
		cudaStatus = cudaMalloc((void**)&((gpu_data[gpu]).pulse_spacing_gpu), sizeof(int));
		if (cudaStatus != cudaSuccess) {
			printf("cudaMalloc pulse_spacing_gpu failed!\n");
			goto Error;
		}
		cudaStatus = cudaMalloc((void**)&((gpu_data[gpu]).max_pulse_distance_gpu), sizeof(int));
		if (cudaStatus != cudaSuccess) {
			printf("cudaMalloc max_pulse_distance_gpu failed!\n");
			goto Error;
		}

		//And set some values that are constant across all data
		cudaStatus = cudaMemcpy(((gpu_data[gpu]).max_bin_gpu), &max_bin, sizeof(int), cudaMemcpyHostToDevice);
		if (cudaStatus != cudaSuccess) {
			printf("cudaMemcpy failed!\n");
			goto Error;
		}
		cudaStatus = cudaMemcpy(((gpu_data[gpu]).pulse_spacing_gpu), &bin_pulse_spacing, sizeof(int), cudaMemcpyHostToDevice);
		if (cudaStatus != cudaSuccess) {
			printf("cudaMemcpy failed!\n");
			goto Error;
		}
		cudaStatus = cudaMemcpy(((gpu_data[gpu]).max_pulse_distance_gpu), &max_pulse_distance, sizeof(int), cudaMemcpyHostToDevice);
		if (cudaStatus != cudaSuccess) {
			printf("cudaMemcpy failed!\n");
			goto Error;
		}

		//Pointer to first photon bin for each channel
		int host_offest_array[max_channels * file_block_size];
		for (int i = 0; i < max_channels * file_block_size; i++) {
			host_offest_array[i] = i * max_tags_length;
		}
		cudaStatus = cudaMemcpy(((gpu_data[gpu]).offset_gpu), host_offest_array, max_channels * file_block_size * sizeof(int), cudaMemcpyHostToDevice);
		if (cudaStatus != cudaSuccess) {
			printf("cudaMemcpy failed!\n");
			goto Error;
		}

		//Set numerator and denominator to 0
		cudaStatus = cudaMemset(((gpu_data[gpu])).coinc_gpu, 0, (((2 * (max_bin)+1) * (2 * (max_bin)+1)) + (max_pulse_distance * 2) * (max_pulse_distance * 2)) * file_block_size * sizeof(long int));
		if (cudaStatus != cudaSuccess) {
			printf("cudaMemset failed!\n");
			goto Error;
		}
	}

	//Create some streams for us to use for GPU parallelism
	cudaStream_t streams[num_gpu][file_block_size];
	for (int gpu = 0; gpu < num_gpu; gpu++) {
		cudaStatus = cudaSetDevice(gpu);
		if (cudaStatus != cudaSuccess) {
			printf("cudaSetDevice failed!  Do you have a CUDA-capable GPU installed?");
			goto Error;
		}
		for (int i = 0; i < file_block_size; i++) {
			cudaStatus = cudaStreamCreate(&streams[gpu][i]);
			if (cudaStatus != cudaSuccess) {
				printf("Failed to create streams %s\n", cudaGetErrorString(cudaStatus));
				goto Error;
			}
		}
	}

	//Create some events to allow us to know if previous transfer has completed
	cudaEvent_t events[num_gpu][file_block_size];
	for (int gpu = 0; gpu < num_gpu; gpu++) {
		cudaStatus = cudaSetDevice(gpu);
		if (cudaStatus != cudaSuccess) {
			printf("cudaSetDevice failed!  Do you have a CUDA-capable GPU installed?");
			goto Error;
		}
		for (int i = 0; i < file_block_size; i++) {
			cudaEventCreate(&events[gpu][i]);
			if (cudaStatus != cudaSuccess) {
				printf("Failed to create events %s\n", cudaGetErrorString(cudaStatus));
				goto Error;
			}
		}
	}

	//Processes files in blocks
	for (int block_num = 0; block_num < blocks_req; block_num++) {
		//Allocate a vector to hold a block of shot_data
		std::vector<shotData> shot_block(file_block_size * num_gpu);

		//Populate the shot_block with data from file
		populateBlock(&shot_block, &filelist, block_num, num_gpu, file_block_size);

		//Sort tags and convert them to bins
		sortAndBinBlock(&shot_block, bin_width, num_gpu, file_block_size);
		//printShotChannelBins(&(shot_block[0]), 1);

		// cudaDeviceSynchronize waits for the kernel to finish, and returns
		// any errors encountered during the launch.
		/*cudaStatus = cudaDeviceSynchronize();
		if (cudaStatus != cudaSuccess) {
		printf("cudaDeviceSynchronize returned error code %d after launching addKernel!\n", cudaStatus);
		goto Error;
		}*/
		for (int gpu = 0; gpu < num_gpu; gpu++) {
			cudaStatus = cudaSetDevice(gpu);
			if (cudaStatus != cudaSuccess) {
				printf("cudaSetDevice failed!  Do you have a CUDA-capable GPU installed?");
				goto Error;
			}

			// Check for any errors launching the kernel
			cudaStatus = cudaGetLastError();
			if (cudaStatus != cudaSuccess) {
				printf("addKernel launch failed: %s\n", cudaGetErrorString(cudaStatus));
				goto Error;
			}

			//Asyncronously load data to GPU
			for (int shot_file_num = 0; shot_file_num < file_block_size; shot_file_num++) {
				int block_file_num = shot_file_num * num_gpu + gpu;
				if ((shot_block)[block_file_num].file_load_completed) {
					int num_channels = (shot_block)[block_file_num].channel_list.size();
					if (num_channels >= 2) {


						std::vector<long int*> photon_bins;
						long int start_and_end_clocks[2];
						std::vector<int> photon_bins_length;
						photon_bins.resize(max_channels);
						photon_bins_length.resize(max_channels);

						start_and_end_clocks[0] = (shot_block)[block_file_num].sorted_clock_bins[1][0];
						start_and_end_clocks[1] = (shot_block)[block_file_num].sorted_clock_bins[0][0];
						for (int i = 0; i < num_channels; i++) {
							photon_bins[i] = &((shot_block)[block_file_num].sorted_photon_bins[i][0]);
							photon_bins_length[i] = (shot_block)[block_file_num].sorted_photon_tag_pointers[i];
						}

						//Synch to ensure previous asnyc memcopy has finished otherwise we'll start overwriting writing to data that may be DMA'd
						cudaStatus = cudaEventSynchronize(events[gpu][shot_file_num]);
						if (cudaStatus != cudaSuccess) {
							printf("Event synch failed\n");
							goto Error;
						}

						//Write photon bins to memory
						int photon_offset = shot_file_num * max_channels * max_tags_length;
						for (int i = 0; i < photon_bins_length.size(); i++) {
							memcpy(pinned_photon_bins[gpu] + photon_offset, (photon_bins)[i], (photon_bins_length)[i] * sizeof(long int));
							cudaStatus = cudaMemcpyAsync((gpu_data[gpu]).photon_bins_gpu + photon_offset, pinned_photon_bins[gpu] + photon_offset, (photon_bins_length)[i] * sizeof(long int), cudaMemcpyHostToDevice, streams[gpu][shot_file_num]);
							if (cudaStatus != cudaSuccess) {
								printf("cudaMemcpy photon_bins failed!\n");
								goto Error;
							}
							photon_offset += max_tags_length;
						}

						int clock_offset = shot_file_num * 2;
						//And other parameters
						memcpy(pinned_start_and_end_clocks[gpu] + clock_offset, start_and_end_clocks, 2 * sizeof(long int));
						cudaStatus = cudaMemcpyAsync((gpu_data[gpu]).start_and_end_clocks_gpu + clock_offset, pinned_start_and_end_clocks[gpu] + clock_offset, 2 * sizeof(long int), cudaMemcpyHostToDevice, streams[gpu][shot_file_num]);
						if (cudaStatus != cudaSuccess) {
							printf("cudaMemcpy clock_offset failed!\n");
							goto Error;
						}

						int length_offset = shot_file_num * max_channels;
						//Can't copy vector to cuda easily
						for (int i = 0; i < photon_bins_length.size(); i++) {
							memcpy(pinned_photon_bins_length[gpu] + i + length_offset, &((photon_bins_length)[i]), sizeof(int));
						}
						cudaStatus = cudaMemcpyAsync((gpu_data[gpu]).photon_bins_length_gpu + length_offset, pinned_photon_bins_length[gpu] + length_offset, max_channels * sizeof(int), cudaMemcpyHostToDevice, streams[gpu][shot_file_num]);
						if (cudaStatus != cudaSuccess) {
							printf("cudaMemcpy length_offset failed!\n");
							goto Error;
						}

						//Create an event to let us know all the async copies have occured
						cudaEventRecord(events[gpu][shot_file_num], streams[gpu][shot_file_num]);
						//Run kernels
						calculateCoincidencesGPU_g3 << <cuda_blocks_numer, threads_per_cuda_block_numer, 0, streams[gpu][shot_file_num] >> > ((gpu_data[gpu]).coinc_gpu, (gpu_data[gpu]).photon_bins_gpu, (gpu_data[gpu]).start_and_end_clocks_gpu, (gpu_data[gpu]).max_bin_gpu, (gpu_data[gpu]).pulse_spacing_gpu, (gpu_data[gpu]).max_pulse_distance_gpu, (gpu_data[gpu]).offset_gpu, (gpu_data[gpu]).photon_bins_length_gpu, num_channels, shot_file_num);
					}
				}
			}
		}
		printf("Sent block %i/%i\n", block_num + 1, blocks_req);
	}
	printf("Finished sending blocks\n");

	for (int gpu = 0; gpu < num_gpu; gpu++) {
		cudaStatus = cudaSetDevice(gpu);
		if (cudaStatus != cudaSuccess) {
			printf("cudaSetDevice failed!  Do you have a CUDA-capable GPU installed?");
			goto Error;
		}
		for (int i = 0; i < file_block_size; i++) {
			cudaStatus = cudaStreamSynchronize(streams[gpu][i]);
			if (cudaStatus != cudaSuccess) {
				printf("cudaDeviceSynchronize returned error code %d after launching addKernel!\n", cudaStatus);
				goto Error;
			}
		}
	}

	//Free pinned memory
	for (int gpu = 0; gpu < num_gpu; gpu++) {
		cudaStatus = cudaSetDevice(gpu);
		if (cudaStatus != cudaSuccess) {
			printf("cudaSetDevice failed!  Do you have a CUDA-capable GPU installed?");
			goto Error;
		}
		cudaFreeHost(pinned_photon_bins[gpu]);
		cudaFreeHost(pinned_photon_bins_length[gpu]);
		cudaFreeHost(pinned_start_and_end_clocks[gpu]);
	}

	//This is to pull the streamed numerator off the GPU
	//Streamed numerator refers to the way the numerator is stored on the GPU where each GPU stream has a seperate numerator
	for (int gpu = 0; gpu < num_gpu; gpu++) {
		cudaStatus = cudaSetDevice(gpu);
		if (cudaStatus != cudaSuccess) {
			printf("cudaSetDevice failed!  Do you have a CUDA-capable GPU installed?");
			goto Error;
		}
		long int *streamed_coinc;
		streamed_coinc = (long int *)malloc((((2 * (max_bin)+1) * (2 * (max_bin)+1)) + (max_pulse_distance * 2) * (max_pulse_distance * 2)) * file_block_size * sizeof(long int));

		// Copy output vector from GPU buffer to host memory.
		cudaStatus = cudaMemcpy(streamed_coinc, (gpu_data[gpu]).coinc_gpu, (((2 * (max_bin)+1) * (2 * (max_bin)+1)) + (max_pulse_distance * 2) * (max_pulse_distance * 2)) * file_block_size * sizeof(long int), cudaMemcpyDeviceToHost);
		if (cudaStatus != cudaSuccess) {
			printf("cudaMemcpy numerator failed!\n");
			free(streamed_coinc);
			goto Error;
		}

		//Collapse streamed coincidence counts down to regular numerator and denominator
		for (int i = 0; i < file_block_size; i++) {
			for (int j = 0; j < (((2 * (max_bin)+1) * (2 * (max_bin)+1)) + (max_pulse_distance * 2) * (max_pulse_distance * 2)); j++) {
				if (j < ((2 * (max_bin)+1) * (2 * (max_bin)+1))) {
					PyList_SetItem(numer, j, PyLong_FromLong(PyLong_AsLong(PyList_GetItem(numer, j)) + streamed_coinc[j + i * (((2 * (max_bin)+1) * (2 * (max_bin)+1)) + (max_pulse_distance * 2) * (max_pulse_distance * 2))]));
				}
				else {
					denom[0] += streamed_coinc[j + i * (((2 * (max_bin)+1) * (2 * (max_bin)+1)) + (max_pulse_distance * 2) * (max_pulse_distance * 2))];
				}
			}
		}
		free(streamed_coinc);
	}

	//Release CUDA device
	for (int gpu = 0; gpu < num_gpu; gpu++) {
		cudaStatus = cudaSetDevice(gpu);
		if (cudaStatus != cudaSuccess) {
			printf("cudaSetDevice failed!  Do you have a CUDA-capable GPU installed?");
			goto Error;
		}
		cudaStatus = cudaDeviceReset();
		if (cudaStatus != cudaSuccess) {
			printf("cudaDeviceReset failed!\n");
		}
	}

Error:
	for (int gpu = 0; gpu < num_gpu; gpu++) {
		cudaStatus = cudaSetDevice(gpu);
		if (cudaStatus != cudaSuccess) {
			printf("cudaSetDevice failed!  Do you have a CUDA-capable GPU installed?");
			goto Error;
		}
		cudaFree((gpu_data[gpu].coinc_gpu));
		cudaFree((gpu_data[gpu].offset_gpu));
		cudaFree((gpu_data[gpu].max_bin_gpu));
		cudaFree((gpu_data[gpu].pulse_spacing_gpu));
		cudaFree((gpu_data[gpu].max_pulse_distance_gpu));
		cudaFree((gpu_data[gpu].photon_bins_length_gpu));
		cudaFree(gpu_data[gpu].photon_bins_gpu);
		cudaFree(gpu_data[gpu].start_and_end_clocks_gpu);
		cudaFreeHost(pinned_photon_bins[gpu]);
		cudaFreeHost(pinned_photon_bins_length[gpu]);
		cudaFreeHost(pinned_start_and_end_clocks[gpu]);
		cudaDeviceReset();
	}
}

DLLEXPORT void getG3Correlations_old(char **file_list, int file_list_length, double max_time, double bin_width, double pulse_spacing, int max_pulse_distance, PyObject *numer, long int *denom) {
	std::vector<char *> filelist(file_list_length);
	//Grab filename and stick it into filelist vector
	for (int i = 0; i < file_list_length; i++) {
		filelist[i] = file_list[i];
	}

	int blocks_req;
	if (file_list_length< (file_block_size * num_gpu)) {
		blocks_req = 1;
	}
	else if ((file_list_length % (file_block_size * num_gpu)) == 0) {
		blocks_req = file_list_length / (file_block_size * num_gpu);
	}
	else {
		blocks_req = file_list_length / (file_block_size * num_gpu) + 1;
	}
	printf("Chunking %i files into %i blocks\n", file_list_length, blocks_req);
	printf("Max Time\tBin Width\tPulse Spacing\tMax Pulse Distance\n");
	printf("%fus\t%fns\t%fus\t%i\n", max_time * 1e6, bin_width * 1e9, pulse_spacing * 1e6, max_pulse_distance);

	int max_bin = (int)round(max_time / bin_width);
	int bin_pulse_spacing = (int)round(pulse_spacing / bin_width);

	//Figure out how many CUDA blocks to chunk the processing up into for the numerator
	int cuda_blocks_numer = 0;
	int threads_per_block_numer = 128;
	if (threads_per_block_numer >= (((2 * (max_bin)+1) * (2 * (max_bin)+1)) + (max_pulse_distance * 2) * (max_pulse_distance * 2))) {
		cuda_blocks_numer = 1;
	}
	else if (((((2 * (max_bin)+1) * (2 * (max_bin)+1)) + (max_pulse_distance * 2) * (max_pulse_distance * 2)) % threads_per_block_numer) == 0) {
		cuda_blocks_numer = (((2 * (max_bin)+1) * (2 * (max_bin)+1)) + (max_pulse_distance * 2) * (max_pulse_distance * 2)) / threads_per_block_numer;
	}
	else {
		cuda_blocks_numer = (((2 * (max_bin)+1) * (2 * (max_bin)+1)) + (max_pulse_distance * 2) * (max_pulse_distance * 2)) / threads_per_block_numer + 1;
	}

	cudaError_t cudaStatus;

	//Pointers for our various pinned memory for host-GPU DMA
	long int* pinned_photon_bins[num_gpu];
	long int* pinned_start_and_end_clocks[num_gpu];
	int* pinned_photon_bins_length[num_gpu];

	//Load some stuff to the GPU we will use permenantly
	//Allocate memory on GPU for various things
	gpuData gpu_data[num_gpu];

	for (int gpu = 0; gpu < num_gpu; gpu++) {

		cudaStatus = cudaSetDevice(gpu);
		if (cudaStatus != cudaSuccess) {
			printf("cudaSetDevice failed!  Do you have a CUDA-capable GPU installed?");
			goto Error;
		}

		cudaMallocHost((long int**)&pinned_photon_bins[gpu], max_tags_length * max_channels * file_block_size * sizeof(long int));
		cudaMallocHost((long int**)&pinned_start_and_end_clocks[gpu], 2 * file_block_size * sizeof(long int));
		cudaMallocHost((int**)&pinned_photon_bins_length[gpu], max_channels * file_block_size * sizeof(int));

		cudaStatus = cudaMalloc((void**)&((gpu_data[gpu]).photon_bins_gpu), max_channels * max_tags_length * file_block_size * sizeof(long int));
		if (cudaStatus != cudaSuccess) {
			printf("cudaMalloc photon_bins_gpu failed\n");
			printf("%s\n", cudaGetErrorString(cudaStatus));
			goto Error;
		}
		cudaStatus = cudaMalloc((void**)&((gpu_data[gpu]).offset_gpu), max_channels * file_block_size * sizeof(int));
		if (cudaStatus != cudaSuccess) {
			printf("cudaMalloc offset_gpu failed!\n");
			goto Error;
		}
		cudaStatus = cudaMalloc((void**)&((gpu_data[gpu]).photon_bins_length_gpu), max_channels * file_block_size * sizeof(int));
		if (cudaStatus != cudaSuccess) {
			printf("cudaMalloc photon_bins_length_gpu failed!\n");
			goto Error;
		}
		cudaStatus = cudaMalloc((void**)&(gpu_data[gpu].coinc_gpu), (((2 * (max_bin)+1) * (2 * (max_bin)+1)) + (max_pulse_distance * 2) * (max_pulse_distance * 2)) * file_block_size * sizeof(long int));
		if (cudaStatus != cudaSuccess) {
			printf("cudaMalloc numer_gpu failed!\n");
			goto Error;
		}
		cudaStatus = cudaMalloc((void**)&((gpu_data[gpu]).start_and_end_clocks_gpu), 2 * file_block_size * sizeof(long int));
		if (cudaStatus != cudaSuccess) {
			printf("cudaMalloc start_and_end_clocks_gpu failed!\n");
			goto Error;
		}
		cudaStatus = cudaMalloc((void**)&((gpu_data[gpu]).max_bin_gpu), sizeof(int));
		if (cudaStatus != cudaSuccess) {
			printf("cudaMalloc max_bin_gpu failed!\n");
			goto Error;
		}
		cudaStatus = cudaMalloc((void**)&((gpu_data[gpu]).pulse_spacing_gpu), sizeof(int));
		if (cudaStatus != cudaSuccess) {
			printf("cudaMalloc pulse_spacing_gpu failed!\n");
			goto Error;
		}
		cudaStatus = cudaMalloc((void**)&((gpu_data[gpu]).max_pulse_distance_gpu), sizeof(int));
		if (cudaStatus != cudaSuccess) {
			printf("cudaMalloc max_pulse_distance_gpu failed!\n");
			goto Error;
		}

		//And set some values that are constant across all data
		cudaStatus = cudaMemcpy(((gpu_data[gpu]).max_bin_gpu), &max_bin, sizeof(int), cudaMemcpyHostToDevice);
		if (cudaStatus != cudaSuccess) {
			printf("cudaMemcpy failed!\n");
			goto Error;
		}
		cudaStatus = cudaMemcpy(((gpu_data[gpu]).pulse_spacing_gpu), &bin_pulse_spacing, sizeof(int), cudaMemcpyHostToDevice);
		if (cudaStatus != cudaSuccess) {
			printf("cudaMemcpy failed!\n");
			goto Error;
		}
		cudaStatus = cudaMemcpy(((gpu_data[gpu]).max_pulse_distance_gpu), &max_pulse_distance, sizeof(int), cudaMemcpyHostToDevice);
		if (cudaStatus != cudaSuccess) {
			printf("cudaMemcpy failed!\n");
			goto Error;
		}

		//Pointer to first photon bin for each channel
		int host_offest_array[max_channels * file_block_size];
		for (int i = 0; i < max_channels * file_block_size; i++) {
			host_offest_array[i] = i * max_tags_length;
		}
		cudaStatus = cudaMemcpy(((gpu_data[gpu]).offset_gpu), host_offest_array, max_channels * file_block_size * sizeof(int), cudaMemcpyHostToDevice);
		if (cudaStatus != cudaSuccess) {
			printf("cudaMemcpy failed!\n");
			goto Error;
		}

		//Set numerator and denominator to 0
		cudaStatus = cudaMemset(((gpu_data[gpu])).coinc_gpu, 0, (((2 * (max_bin)+1) * (2 * (max_bin)+1)) + (max_pulse_distance * 2) * (max_pulse_distance * 2)) * file_block_size * sizeof(long int));
		if (cudaStatus != cudaSuccess) {
			printf("cudaMemset failed!\n");
			goto Error;
		}
	}

	//Create some streams for us to use for GPU parallelism
	cudaStream_t streams[num_gpu][file_block_size];
	for (int gpu = 0; gpu < num_gpu; gpu++) {
		cudaStatus = cudaSetDevice(gpu);
		if (cudaStatus != cudaSuccess) {
			printf("cudaSetDevice failed!  Do you have a CUDA-capable GPU installed?");
			goto Error;
		}
		for (int i = 0; i < file_block_size; i++) {
			cudaStatus = cudaStreamCreate(&streams[gpu][i]);
			if (cudaStatus != cudaSuccess) {
				printf("Failed to create streams %s\n", cudaGetErrorString(cudaStatus));
				goto Error;
			}
		}
	}

	//Create some events to allow us to know if previous transfer has completed
	cudaEvent_t events[num_gpu][file_block_size];
	for (int gpu = 0; gpu < num_gpu; gpu++) {
		cudaStatus = cudaSetDevice(gpu);
		if (cudaStatus != cudaSuccess) {
			printf("cudaSetDevice failed!  Do you have a CUDA-capable GPU installed?");
			goto Error;
		}
		for (int i = 0; i < file_block_size; i++) {
			cudaEventCreate(&events[gpu][i]);
			if (cudaStatus != cudaSuccess) {
				printf("Failed to create events %s\n", cudaGetErrorString(cudaStatus));
				goto Error;
			}
		}
	}

	//Processes files in blocks
	for (int block_num = 0; block_num < blocks_req; block_num++) {
		//Allocate a vector to hold a block of shot_data
		std::vector<shotData> shot_block(file_block_size * num_gpu);

		//Populate the shot_block with data from file
		populateBlock(&shot_block, &filelist, block_num, num_gpu, file_block_size);

		//Sort tags and convert them to bins
		sortAndBinBlock(&shot_block, bin_width, num_gpu, file_block_size);
		//printShotChannelBins(&(shot_block[0]), 1);

		// cudaDeviceSynchronize waits for the kernel to finish, and returns
		// any errors encountered during the launch.
		/*cudaStatus = cudaDeviceSynchronize();
		if (cudaStatus != cudaSuccess) {
		printf("cudaDeviceSynchronize returned error code %d after launching addKernel!\n", cudaStatus);
		goto Error;
		}*/
		for (int gpu = 0; gpu < num_gpu; gpu++) {
			cudaStatus = cudaSetDevice(gpu);
			if (cudaStatus != cudaSuccess) {
				printf("cudaSetDevice failed!  Do you have a CUDA-capable GPU installed?");
				goto Error;
			}

			// Check for any errors launching the kernel
			cudaStatus = cudaGetLastError();
			if (cudaStatus != cudaSuccess) {
				printf("addKernel launch failed: %s\n", cudaGetErrorString(cudaStatus));
				goto Error;
			}

			//Asyncronously load data to GPU
			for (int shot_file_num = 0; shot_file_num < file_block_size; shot_file_num++) {
				int block_file_num = shot_file_num * num_gpu + gpu;
				if ((shot_block)[block_file_num].file_load_completed) {
					int num_channels = (shot_block)[block_file_num].channel_list.size();
					if (num_channels >= 2) {

						std::vector<long int*> photon_bins;
						long int start_and_end_clocks[2];
						std::vector<int> photon_bins_length;
						photon_bins.resize(max_channels);
						photon_bins_length.resize(max_channels);

						start_and_end_clocks[0] = (shot_block)[block_file_num].sorted_clock_bins[1][0];
						start_and_end_clocks[1] = (shot_block)[block_file_num].sorted_clock_bins[0][0];
						for (int i = 0; i < num_channels; i++) {
							photon_bins[i] = &((shot_block)[block_file_num].sorted_photon_bins[i][0]);
							photon_bins_length[i] = (shot_block)[block_file_num].sorted_photon_tag_pointers[i];
						}

						//Synch to ensure previous asnyc memcopy has finished otherwise we'll start overwriting writing to data that may be DMA'd
						cudaStatus = cudaEventSynchronize(events[gpu][shot_file_num]);
						if (cudaStatus != cudaSuccess) {
							printf("Event synch failed\n");
							goto Error;
						}

						//Write photon bins to memory
						int photon_offset = shot_file_num * max_channels * max_tags_length;
						for (int i = 0; i < photon_bins_length.size(); i++) {
							memcpy(pinned_photon_bins[gpu] + photon_offset, (photon_bins)[i], (photon_bins_length)[i] * sizeof(long int));
							cudaStatus = cudaMemcpyAsync((gpu_data[gpu]).photon_bins_gpu + photon_offset, pinned_photon_bins[gpu] + photon_offset, (photon_bins_length)[i] * sizeof(long int), cudaMemcpyHostToDevice, streams[gpu][shot_file_num]);
							if (cudaStatus != cudaSuccess) {
								printf("cudaMemcpy photon_bins failed!\n");
								goto Error;
							}
							photon_offset += max_tags_length;
						}

						int clock_offset = shot_file_num * 2;
						//And other parameters
						memcpy(pinned_start_and_end_clocks[gpu] + clock_offset, start_and_end_clocks, 2 * sizeof(long int));
						cudaStatus = cudaMemcpyAsync((gpu_data[gpu]).start_and_end_clocks_gpu + clock_offset, pinned_start_and_end_clocks[gpu] + clock_offset, 2 * sizeof(long int), cudaMemcpyHostToDevice, streams[gpu][shot_file_num]);
						if (cudaStatus != cudaSuccess) {
							printf("cudaMemcpy clock_offset failed!\n");
							goto Error;
						}

						int length_offset = shot_file_num * max_channels;
						//Can't copy vector to cuda easily
						for (int i = 0; i < photon_bins_length.size(); i++) {
							memcpy(pinned_photon_bins_length[gpu] + i + length_offset, &((photon_bins_length)[i]), sizeof(int));
						}
						cudaStatus = cudaMemcpyAsync((gpu_data[gpu]).photon_bins_length_gpu + length_offset, pinned_photon_bins_length[gpu] + length_offset, max_channels * sizeof(int), cudaMemcpyHostToDevice, streams[gpu][shot_file_num]);
						if (cudaStatus != cudaSuccess) {
							printf("cudaMemcpy length_offset failed!\n");
							goto Error;
						}

						//Create an event to let us know all the async copies have occured
						cudaEventRecord(events[gpu][shot_file_num], streams[gpu][shot_file_num]);
						//Run kernels
						calculateCoincidencesGPU_g3 << <cuda_blocks_numer, threads_per_cuda_block_numer, 0, streams[gpu][shot_file_num] >> > ((gpu_data[gpu]).coinc_gpu, (gpu_data[gpu]).photon_bins_gpu, (gpu_data[gpu]).start_and_end_clocks_gpu, (gpu_data[gpu]).max_bin_gpu, (gpu_data[gpu]).pulse_spacing_gpu, (gpu_data[gpu]).max_pulse_distance_gpu, (gpu_data[gpu]).offset_gpu, (gpu_data[gpu]).photon_bins_length_gpu, num_channels, shot_file_num);
					}
				}
			}
		}
		printf("Sent block %i/%i\n", block_num + 1, blocks_req);
	}
	printf("Finished sending blocks\n");

	for (int gpu = 0; gpu < num_gpu; gpu++) {
		cudaStatus = cudaSetDevice(gpu);
		if (cudaStatus != cudaSuccess) {
			printf("cudaSetDevice failed!  Do you have a CUDA-capable GPU installed?");
			goto Error;
		}
		for (int i = 0; i < file_block_size; i++) {
			cudaStatus = cudaStreamSynchronize(streams[gpu][i]);
			if (cudaStatus != cudaSuccess) {
				printf("cudaDeviceSynchronize returned error code %d after launching addKernel!\n", cudaStatus);
				goto Error;
			}
		}
	}

	//Free pinned memory
	for (int gpu = 0; gpu < num_gpu; gpu++) {
		cudaStatus = cudaSetDevice(gpu);
		if (cudaStatus != cudaSuccess) {
			printf("cudaSetDevice failed!  Do you have a CUDA-capable GPU installed?");
			goto Error;
		}
		cudaFreeHost(pinned_photon_bins[gpu]);
		cudaFreeHost(pinned_photon_bins_length[gpu]);
		cudaFreeHost(pinned_start_and_end_clocks[gpu]);
	}

	//This is to pull the streamed numerator off the GPU
	//Streamed numerator refers to the way the numerator is stored on the GPU where each GPU stream has a seperate numerator
	for (int gpu = 0; gpu < num_gpu; gpu++) {
		cudaStatus = cudaSetDevice(gpu);
		if (cudaStatus != cudaSuccess) {
			printf("cudaSetDevice failed!  Do you have a CUDA-capable GPU installed?");
			goto Error;
		}
		long int *streamed_coinc;
		streamed_coinc = (long int *)malloc((((2 * (max_bin)+1) * (2 * (max_bin)+1)) + (max_pulse_distance * 2) * (max_pulse_distance * 2)) * file_block_size * sizeof(long int));

		// Copy output vector from GPU buffer to host memory.
		cudaStatus = cudaMemcpy(streamed_coinc, (gpu_data[gpu]).coinc_gpu, (((2 * (max_bin)+1) * (2 * (max_bin)+1)) + (max_pulse_distance * 2) * (max_pulse_distance * 2)) * file_block_size * sizeof(long int), cudaMemcpyDeviceToHost);
		if (cudaStatus != cudaSuccess) {
			printf("cudaMemcpy numerator failed!\n");
			free(streamed_coinc);
			goto Error;
		}

		//Collapse streamed coincidence counts down to regular numerator and denominator
		for (int i = 0; i < file_block_size; i++) {
			for (int j = 0; j < (((2 * (max_bin)+1) * (2 * (max_bin)+1)) + (max_pulse_distance * 2) * (max_pulse_distance * 2)); j++) {
				if (j < ((2 * (max_bin)+1) * (2 * (max_bin)+1))) {
					PyList_SetItem(numer, j, PyLong_FromLong(PyLong_AsLong(PyList_GetItem(numer, j)) + streamed_coinc[j + i * (((2 * (max_bin)+1) * (2 * (max_bin)+1)) + (max_pulse_distance * 2) * (max_pulse_distance * 2))]));
				}
				else {
					denom[0] += streamed_coinc[j + i * (((2 * (max_bin)+1) * (2 * (max_bin)+1)) + (max_pulse_distance * 2) * (max_pulse_distance * 2))];
				}
			}
		}
		free(streamed_coinc);
	}

	//Release CUDA device
	for (int gpu = 0; gpu < num_gpu; gpu++) {
		cudaStatus = cudaSetDevice(gpu);
		if (cudaStatus != cudaSuccess) {
			printf("cudaSetDevice failed!  Do you have a CUDA-capable GPU installed?");
			goto Error;
		}
		cudaStatus = cudaDeviceReset();
		if (cudaStatus != cudaSuccess) {
			printf("cudaDeviceReset failed!\n");
		}
	}

Error:
	for (int gpu = 0; gpu < num_gpu; gpu++) {
		cudaStatus = cudaSetDevice(gpu);
		if (cudaStatus != cudaSuccess) {
			printf("cudaSetDevice failed!  Do you have a CUDA-capable GPU installed?");
			goto Error;
		}
		cudaFree((gpu_data[gpu].coinc_gpu));
		cudaFree((gpu_data[gpu].offset_gpu));
		cudaFree((gpu_data[gpu].max_bin_gpu));
		cudaFree((gpu_data[gpu].pulse_spacing_gpu));
		cudaFree((gpu_data[gpu].max_pulse_distance_gpu));
		cudaFree((gpu_data[gpu].photon_bins_length_gpu));
		cudaFree(gpu_data[gpu].photon_bins_gpu);
		cudaFree(gpu_data[gpu].start_and_end_clocks_gpu);
		cudaFreeHost(pinned_photon_bins[gpu]);
		cudaFreeHost(pinned_photon_bins_length[gpu]);
		cudaFreeHost(pinned_start_and_end_clocks[gpu]);
		cudaDeviceReset();
	}

}