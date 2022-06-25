#version 440

//this compute shader carries out the diffusion of the pheromone trails and
//uses this and the map infomation to colour the final texture that is used in the display
//it is the last shader used and so also resets the relevant values to prevent any build up in time

//===========================================================================


//loading in buffers sent by CPU
layout(binding = 1) buffer pheremonesToFood {		//pheromones ants leave when finding food
	float pheremonesFood [  ];
};
layout(binding = 2) buffer pheremonesToNest {		//pheromones ants leave when finding a nest
	float pheremonesNest [  ];
};
layout(binding = 3) buffer pheremonesToFoodBack {	//background array for storing diffused values
	float pheremonesFoodBack [  ];					//needed to have an "instantaneous" global update
};
layout(binding = 4) buffer pheremonesToNestBack {   //background array for storing diffused values
	float pheremonesNestBack [  ];					//needed to have an "instantaneous" global update
};
layout(binding = 5) buffer foodBuffer {				//stores all the map infomation, food, walls, nests and particle positions
	float food [  ];
};
layout(binding = 8) buffer foodBufferBack {			//needed to have an "instantaneous" global update
	float foodBack [  ];
};
layout(rgba8,binding=7)  uniform writeonly image2D pheremoneDisplay; //output to buffer
layout(rgba8,binding=6)  uniform writeonly image2D pheremoneDisplayAlt; //output to buffer

layout(local_size_x= 20, local_size_y=20, local_size_z = 1) in;		 //reciving segment for parallelisation

//loading in infomation and setting globals
uniform float decayWeight;		//pheromone params
uniform float diffusionWeight;
uniform float heatDecayWeight;	
uniform int W;					//resolution shaders
uniform int H;
uniform int frameNum;
float weights[9] = float[](		//diffusion weights
    1/16.0, 1/8.0, 1/16.0, 
    1/8.0 , 1/4.0, 1/8.0 , 
    1/16.0, 1/8.0, 1/16.0
	);

//===========================================================================

//heler function that calculates the values that will be added
//to a current pixel due to diffusion.
//weights are used in a gaussian for more accurate diffusion (corners should recieve less)
vec3 diffuseIDX(int i, int j){
	float valueFood = 0;										 //storing food value											
	int c = 0;													 //counter
	for (int ii=-1;ii<=1;ii++){								
		for(int jj=-1;jj<=1;jj++){							     //kernel loop with gaussian weighted matrix
			valueFood+=pheremonesFood[i+ii+(j+jj)*W]*weights[c]; //adding diffused values from surroundings to current location
			c++;
		}
	}
	float valueNest = 0;										 //storing nest value	
	c = 0;														 //resetting counter
	for (int ii=-1;ii<=1;ii++){
		for(int jj=-1;jj<=1;jj++){							     //kernel loop with gaussian weighted matrix
			valueNest+=pheremonesNest[i+ii+(j+jj)*W]*weights[c]; //adding diffused values from surroundings to current location
			c++;
		}
	}
	float valueHeat = 0;										 //storing nest value	
	
	if (frameNum%3==0){
		c = 0;														 //resetting counter
		for (int ii=-1;ii<=1;ii++){
			for(int jj=-1;jj<=1;jj++){							     //kernel loop with gaussian weighted matrix
				valueHeat+=food[i+ii+(j+jj)*W+3*W*H]*weights[c]; //adding diffused values from surroundings to current location
				c++;
			}
		}
	}
	return vec3(valueFood,valueNest,valueHeat);							 //returning values in vec2
}

//===========================================================================
void main(){
	
	//loading in positional infomation
	int i = int(gl_GlobalInvocationID.x);						 //x					
    int j = int(gl_GlobalInvocationID.y);						 //y
	int idx = i+j*W;											 //2D->1D
																 
	//getting value infomation for the update					 
	float origValueFood		= pheremonesFood[idx];				 //current value in primary buffer
	float origValueNest		= pheremonesNest[idx];				 //current value in primary buffer
	float origValueHeat     = foodBack[idx+3*W*H];
	vec3 diffused			= diffuseIDX(i,j);					 //carry out diffusion into cell
	float diffusedValueFood = diffused.x;						
	float diffusedValueNest = diffused.y;
	float diffusedValueHeat = diffused.z;

	//carryig out mixing of original and diffused values for food
	pheremonesFoodBack[idx] = max(0,origValueFood * (1.0-diffusionWeight*0.1) + diffusedValueFood * diffusionWeight*0.1); //"""""""""this was not used previously!!!!!!!!!!""""""""""
	pheremonesFoodBack[idx]*=(1.0-decayWeight*0.5);
	float valueFood =pheremonesFoodBack[idx];

	//carryig out mixing of original and diffused values for nest
	pheremonesNestBack[idx] = max(0,origValueNest * (1.0-diffusionWeight*0.1) + diffusedValueNest * diffusionWeight*0.1);
	pheremonesNestBack[idx]*=(1.0-decayWeight*0.5);
	float valueNest=pheremonesNestBack[idx];
	
	foodBack[idx+3*W*H] = origValueHeat;

	if (frameNum%3==0){
		foodBack[idx+3*W*H] = origValueHeat * (1.0-diffusionWeight*0.1) + diffusedValueHeat * diffusionWeight*0.44;
		foodBack[idx+3*W*H]*=(1.0-heatDecayWeight);
//		foodBack[idx+3*W*H]*=(0.395);
		if (foodBack[idx+3*W*H]>-0.1){
			foodBack[idx+3*W*H]=0.0;
		}
	}
	float valueHeat=foodBack[idx+3*W*H];
	

	//setting up colours
	vec4 colFood = vec4(0,valueFood*0.9,valueFood*0.3,0.3);						//food pheromones shown in blue
	vec4 colNest = vec4(valueNest*0.2,valueNest*0.1,valueNest*0.9,0.3);						//nest pheromones shown in red
	vec4 colHeat = vec4(abs(valueHeat),0.2*abs(valueHeat),abs(valueHeat)*0.2,1.0);
	vec4 colDetail;												//colour for showing map infomation

	//conditionals to define colDetail
	if (food[idx]<-1000){										//if its a wall, display in grey and remove pheromones
		 colDetail = vec4(0.5,0.5,0.5,1.0);						//grey
		 pheremonesNestBack[idx] = 0.0;							//removing in back
		 pheremonesFoodBack[idx] = 0.0;	
		 pheremonesNest[idx] = 0.0;							
		 pheremonesFood[idx] = 0.0;
		 colFood=vec4(0.0,0.0,0.0,1.0);
		 colNest=vec4(0.0,0.0,0.0,1.0);
	}
	if (food[idx]>1){											//if food, display in green 
		colDetail = vec4(0,1.0,0,1.0);							//green
	}
	if (food[idx+W*H]>0){										//if its a nest (stored in a "deeper" layer, hence the + W*H)
		colDetail = vec4(1.0,1.0,0.2,1.0);						//display in yellow
	}

	

	if (food[idx]>=0 && food[idx+2*W*H]>0){														//if it is a particle show white
		imageStore(pheremoneDisplay,ivec2(gl_GlobalInvocationID.xy),vec4(1.0,1.0,1.0,0.5));
//		imageStore(pheremoneDisplayAlt,ivec2(gl_GlobalInvocationID.xy),vec4(1.0,1.0,1.0,0.5));

	}
	else{									//if a particle is not here show the combination of pheromones and map details
		imageStore(pheremoneDisplay,ivec2(gl_GlobalInvocationID.xy),colHeat+colFood+colDetail+colNest);
//		imageStore(pheremoneDisplayAlt,ivec2(gl_GlobalInvocationID.xy),colHeat+colNest+colDetail);
	}
	
	
	//resetting background arrays to zero to prevent build up
	//resetting particle positions in food array
	foodBack[idx+W*H*2 ] = 0.0;
	food[idx+W*H*2]      = 0.0;
	foodBack[idx]        = 0.0;

}

