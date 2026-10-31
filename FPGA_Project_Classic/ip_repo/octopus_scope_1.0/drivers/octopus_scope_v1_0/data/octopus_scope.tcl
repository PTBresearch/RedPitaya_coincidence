# SPDX-FileCopyrightText: 2024 Physikalisch-Technische Bundesanstalt (PTB), German National Metrology Institute
# SPDX-License-Identifier: Apache-2.0



proc generate {drv_handle} {
	xdefine_include_file $drv_handle "xparameters.h" "octopus_scope" "NUM_INSTANCES" "DEVICE_ID"  "C_S00_AXI_BASEADDR" "C_S00_AXI_HIGHADDR"
}
