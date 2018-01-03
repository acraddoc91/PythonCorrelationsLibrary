from corrLib import count_tags
data_directory = "C:/Users/Ryd Berg/Downloads/"
data_folder = data_directory+"g2_benchmark/"
max_time = 1e-6
bin_width = 1e-9
pulse_spacing = 100e-6
max_pulse_distance = 4
count_tags(data_folder,max_time,bin_width,pulse_spacing,max_pulse_distance)