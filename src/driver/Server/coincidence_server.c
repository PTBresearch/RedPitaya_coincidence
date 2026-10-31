// SPDX-FileCopyrightText: 2016 Anton Potocnik
// SPDX-FileCopyrightText: 2016-2020 Pavel Demin
// SPDX-FileCopyrightText: 2020 Physikalisch-Technische Bundesanstalt (PTB), German National Metrology Institute
// SPDX-License-Identifier: GPL-3.0-or-later
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <https://www.gnu.org/licenses/gpl-3.0.html>.

/*
FPGA Project: iTracker_mm
Server for setting configuration and reading data from FPGA

16.12.2016 by Anton Potocnik
Modified Pavel Demin's server.c
08.06.2020 Modified by Mattias Misera PTB
*/

#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <string.h>
#include <signal.h>
#include <unistd.h>
#include <fcntl.h>
#include <math.h>
#include <sys/mman.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <time.h>
#include <sys/types.h> 
#include <errno.h> 
#include <netdb.h> 
 

#define START 0
#define STOP 1

#define DEBUG_LEVEL_RUN 1
#define DEBUG_LEVEL_START 1

// This must be of type `volatile` to prevent
// the compiler from optimizing away the
// while loop condition.
volatile sig_atomic_t stop;




//##################################################################
//  Main ... #######################################################
//##################################################################
int main(int argc, char *argv[])
{
  int fd, j, sock_server, sock_client, size, yes = 1, nsmpl, navg, rx;
  void *sys_bus_1;
  void *base_address;
  char *memory = "/dev/mem";
  uint32_t naverages=0, nsamples=0, timing=0;
  struct sockaddr_in addr;
  uint32_t command, address_offset, value, tmp;
  //RedPitaya's sample buffer length
  const unsigned long BUF = (8*1024);
  int32_t sampel_buffer[BUF];
  uint64_t buffer[1];
  int32_t in_buffer[1024];
  int32_t   int32_buffer [1024];
  uint32_t  uint32_buffer[1024];
  clock_t time_begin;
  double time_spent;
    
//#############################################################################
// map FPGA register into memory locations ...
//#############################################################################
  if((fd = open(memory, O_RDWR | O_SYNC)) < 0)
  {
    perror("open");
    return EXIT_FAILURE;
  }
  sys_bus_1       = mmap(NULL, 0x10000, PROT_READ|PROT_WRITE, MAP_SHARED, fd, 0x40100000);

  if((sock_server = socket(AF_INET, SOCK_STREAM, 0)) < 0)
 {
    perror("socket");
    return EXIT_FAILURE;
  }
  setsockopt(sock_server, SOL_SOCKET, SO_REUSEADDR, (void *)&yes , sizeof(yes));
  /* setup listening address */
  memset(&addr, 0, sizeof(addr));
  addr.sin_family = AF_INET;
  addr.sin_addr.s_addr = htonl(INADDR_ANY);
  addr.sin_port = htons(1001);
  if(bind(sock_server, (struct sockaddr *)&addr, sizeof(addr)) < 0)
  {
    perror("bind");
    return EXIT_FAILURE;
  }
//##############################################################################################################################
//  Base configuration for           ###########################################################################################
//##############################################################################################################################


		
  while(1)
  {
        listen(sock_server, 1);
        #if defined(DEBUG_LEVEL_START)
        printf("####################################################################\n");
        printf("Listening on port 1001 ...\n");
        printf("####################################################################\n");        
        #endif // DEBUG_LEVEL_START

        if((sock_client = accept(sock_server, NULL, NULL)) < 0)		//wait for a client
        {
            perror("accept");
            return EXIT_FAILURE;
        }else{
          printf("accept current client ...\n");					// a client has connected 
        }
        
        while(1) //MSG_WAITALL
        {
          rx = recv(sock_client, in_buffer, 3 * sizeof(uint32_t), MSG_DONTWAIT);
          command           = in_buffer[0];       					// 
          address_offset    = in_buffer[1];       					// address offset, example 0x12345
          value             = in_buffer[2];       					// value, (int32_t)
	  if (rx>0)
	      printf("got command, length  %d\n", rx);
          if (rx == 0) {											// a client has disconnected 

              break;
          }
          if(rx > 0)                  // recived data
          {   
              //##############################################################################################################################
              // Reset all counters                                            ###############################################################
              //##############################################################################################################################
              if(command == 1){	
               
                *((uint32_t *)(sys_bus_1 + address_offset + 0x00)) = 1;				                  // 
				*((uint32_t *)(sys_bus_1 + address_offset + 0x00)) = 0;				                  // 

              //##############################################################################################################################
              //                                                               ##############################################################
              //##############################################################################################################################
			  }else if(command == 2){
				int index = 0;
                base_address = sys_bus_1;  
                
                if(address_offset == 0x00100){
				int32_buffer[index++]  = (*(uint32_t *)(base_address + 0x00100));   	//cnt_detector_1_fly;               
                int32_buffer[index++]  = (0);     										// index immer 0
				}				
                if(address_offset == 0x00104){
				int32_buffer[index++]  = (*(uint32_t *)(base_address + 0x00104));   	// cnt_detector_1_100ms;               
                int32_buffer[index++]  = (*(uint32_t *)(base_address + 0x00400));     	//  
				}				
                if(address_offset == 0x00104){
				int32_buffer[index++]  = (*(uint32_t *)(base_address + 0x00108));   	// cnt_detector_1_1;               
                int32_buffer[index++]  = (*(uint32_t *)(base_address + 0x00404));     	// 
				}				
                if(address_offset == 0x00104){
				int32_buffer[index++]  = (*(uint32_t *)(base_address + 0x0010C));   	// cnt_detector_1_2s;               
                int32_buffer[index++]  = (*(uint32_t *)(base_address + 0x00408));     	//  
				}				
                if(address_offset == 0x00104){
				int32_buffer[index++]  = (*(uint32_t *)(base_address + 0x00110));   	// cnt_detector_5s;               
                int32_buffer[index++]  = (*(uint32_t *)(base_address + 0x0040C));     	// index 100ms 
				}				
                if(address_offset == 0x00104){
				int32_buffer[index++]  = (*(uint32_t *)(base_address + 0x00114));   	// cnt_detector_1_10ss;               
                int32_buffer[index++]  = (*(uint32_t *)(base_address + 0x00410));     	// 
				}				

                if(address_offset == 0x00200){
				int32_buffer[index++]  = (*(uint32_t *)(base_address + 0x00200));   	//cnt_detector_2_fly;               
                int32_buffer[index++]  = (0);     										// index immer 0
				}				
                if(address_offset == 0x00204){
				int32_buffer[index++]  = (*(uint32_t *)(base_address + 0x00204));   	// cnt_detector_2_100ms;               
                int32_buffer[index++]  = (*(uint32_t *)(base_address + 0x00400));     	//  
				}				
                if(address_offset == 0x00208){
				int32_buffer[index++]  = (*(uint32_t *)(base_address + 0x00208));   	// cnt_detector_2_1;               
                int32_buffer[index++]  = (*(uint32_t *)(base_address + 0x00404));     	// 
				}				
                if(address_offset == 0x0020C){
				int32_buffer[index++]  = (*(uint32_t *)(base_address + 0x0020C));   	// cnt_detector_2_2s;               
                int32_buffer[index++]  = (*(uint32_t *)(base_address + 0x00408));     	//  
				}				
                if(address_offset == 0x00210){
				int32_buffer[index++]  = (*(uint32_t *)(base_address + 0x00210));   	// cnt_detector_5s;               
                int32_buffer[index++]  = (*(uint32_t *)(base_address + 0x0040C));     	//  
				}				
                if(address_offset == 0x00214){
				int32_buffer[index++]  = (*(uint32_t *)(base_address + 0x00214));   	// cnt_detector_2_10ss;               
                int32_buffer[index++]  = (*(uint32_t *)(base_address + 0x00410));     	// 
				}
				
                if(address_offset == 0x00300){
				int32_buffer[index++]  = (*(uint32_t *)(base_address + 0x00100));   	//cnt_channel_1_fly;               
                int32_buffer[index++]  = (0);     										// index immer 0
				}				
                if(address_offset == 0x00304){
				int32_buffer[index++]  = (*(uint32_t *)(base_address + 0x00304));   	// cnt_channel_1_100ms;               
                int32_buffer[index++]  = (*(uint32_t *)(base_address + 0x00400));     	//  
				}				
                if(address_offset == 0x00308){
				int32_buffer[index++]  = (*(uint32_t *)(base_address + 0x00308));   	// cnt_channel_1_1;               
                int32_buffer[index++]  = (*(uint32_t *)(base_address + 0x00404));     	// 
				}				
                if(address_offset == 0x0030C){
				int32_buffer[index++]  = (*(uint32_t *)(base_address + 0x0030C));   	// cnt_channel_1_2s;               
                int32_buffer[index++]  = (*(uint32_t *)(base_address + 0x00408));     	//  
				}				
                if(address_offset == 0x00310){
				int32_buffer[index++]  = (*(uint32_t *)(base_address + 0x00310));   	// cnt_channel_5s;               
                int32_buffer[index++]  = (*(uint32_t *)(base_address + 0x0040C));     	// 
				}				
                if(address_offset == 0x00314){
				int32_buffer[index++]  = (*(uint32_t *)(base_address + 0x00314));   	// cnt_channel_1_10ss;               
                int32_buffer[index++]  = (*(uint32_t *)(base_address + 0x00410));     	// 
				}				

                        
				send(sock_client, int32_buffer, 2 * sizeof(uint32_t), MSG_NOSIGNAL);

              //##############################################################################################################################
              // Read all counter values                                       ##############################################################
              //##############################################################################################################################				
              }else if(command == 10){
				  
				int index = 0;
                base_address = sys_bus_1;  
                
                int32_buffer[index++]  = (*(uint32_t *)(base_address + 0x00100));   	//cnt_detector_1_fly;                 
                int32_buffer[index++]  = (*(uint32_t *)(base_address + 0x00104));                   
                int32_buffer[index++]  = (*(uint32_t *)(base_address + 0x00108));                   
                int32_buffer[index++]  = (*(uint32_t *)(base_address + 0x0010C));                   
                int32_buffer[index++]  = (*(uint32_t *)(base_address + 0x00110));     				
                int32_buffer[index++]  = (*(uint32_t *)(base_address + 0x00114));     				
                int32_buffer[index++]  = (*(uint32_t *)(base_address + 0x00200));     				
                int32_buffer[index++]  = (*(uint32_t *)(base_address + 0x00204));     				
                int32_buffer[index++]  = (*(uint32_t *)(base_address + 0x00208));     				
                int32_buffer[index++]  = (*(uint32_t *)(base_address + 0x0020C));                   
                int32_buffer[index++]  = (*(uint32_t *)(base_address + 0x00210));                   
                int32_buffer[index++]  = (*(uint32_t *)(base_address + 0x00214));                   
                int32_buffer[index++]  = (*(uint32_t *)(base_address + 0x00300));                   
                int32_buffer[index++]  = (*(uint32_t *)(base_address + 0x00304));                   
                int32_buffer[index++]  = (*(uint32_t *)(base_address + 0x00308));                   
                int32_buffer[index++]  = (*(uint32_t *)(base_address + 0x0030C));                   
                int32_buffer[index++]  = (*(uint32_t *)(base_address + 0x00310));                   
                int32_buffer[index++]  = (*(uint32_t *)(base_address + 0x00314));                   
                int32_buffer[index++]  = (*(uint32_t *)(base_address + 0x00400)); 		// index 100ms                  
                int32_buffer[index++]  = (*(uint32_t *)(base_address + 0x00404));                   
                int32_buffer[index++]  = (*(uint32_t *)(base_address + 0x00408));                   
                int32_buffer[index++]  = (*(uint32_t *)(base_address + 0x0040C));                   
                int32_buffer[index++]  = (*(uint32_t *)(base_address + 0x00410));                   

                send(sock_client, int32_buffer, 23 * sizeof(uint32_t), MSG_NOSIGNAL);

              }

              #if defined(DEBUG_LEVEL_RUN)
              //##############################################################################################################################
              //  Print some debug infos....  ################################################################################################
              //##############################################################################################################################
              printf("write command %i ...\t", command);
              printf("write address_offset [hex] %x ...\t", address_offset);
              printf("write value [hex] %x ...\n", value);
              #endif // debug
              
	      } // if recived data
    } // while(1) if connect
    close(sock_client);
  } // while(1) Listening on port
  close(sock_server);
  return EXIT_SUCCESS;
}

/*
cnt_detector_1_fly;   
cnt_detector_1_100ms; 
cnt_detector_1_1s;    
cnt_detector_1_2s;    
cnt_detector_1_5s;    
cnt_detector_1_10s;   
cnt_detector_2_fly;   
cnt_detector_2_100ms; 
cnt_detector_2_1s;    
cnt_detector_2_2s;    
cnt_detector_2_5s;    
cnt_detector_2_10s;   
cnt_channel_1_fly;    
cnt_channel_1_100ms;  
cnt_channel_1_1s;     
cnt_channel_1_2s;     
cnt_channel_1_5s;     
cnt_channel_1_10s;    
index_100ms;          
index_1s;             
index_2s;             
index_5s;             
index_10s;            
*/
