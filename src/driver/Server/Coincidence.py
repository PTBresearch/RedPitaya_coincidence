# SPDX-FileCopyrightText: 2024 Physikalisch-Technische Bundesanstalt (PTB), German National Metrology Institute
# SPDX-License-Identifier: Apache-2.0

## connect to RedPitaya

import socket
import struct
from time import sleep
import numpy as np
import matplotlib.pyplot as plt

server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
server.connect(('C23022', 1001))
request = struct.pack("<III", 10, 0, 0)
#request = struct.pack("<III", 2, 0, 0)

res=[]

try:
    for i in range(2*10):
    #while request != 'Q':      
        if request:
            server.send(request)
            response = server.recv(92)
            samples = struct.unpack("<23I", response)
            print(i,':  Index(1 s): ', samples[19], '  cnt det 1: ', samples[2])
            res.append(samples)
        #request = 'Q'
        sleep(1)
        
except KeyboardInterrupt:
    server.close()
    
dat = np.array(res)
np.savetxt('test_1.out', dat, delimiter='\t')

server.close()
plt.plot(dat[:,2],  label = 'cnt det 1')
plt.plot(dat[:,8],  label = 'cnt det 2')
plt.plot(dat[:,14], label = 'cnt ch 1')
plt.legend()
plt.show()

