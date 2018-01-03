mat_directory = "C:/Users/Ryd Berg/Google Drive/Rydberg Experiment/Matlab/CorrelationCalculations/For Sandy"
data_directory = "C:/Users/Ryd Berg/Downloads/"

from corrLib import g2ToFile,g3ToFile,g2ToFile_channelPair

data_folder = data_directory+"g2_benchmark/"
#data_folder = data_directory+"test_files/"
mat_file = mat_directory+"g3_benchmark_new"
max_time = 0.5e-6
bin_width = 10e-9
pulse_spacing = 100e-6
max_pulse_distance = 4
g3ToFile(data_folder,mat_file,max_time,bin_width,pulse_spacing,max_pulse_distance)