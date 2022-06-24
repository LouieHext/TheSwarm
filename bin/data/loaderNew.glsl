#version 440


//this compute shader loads in the data sent by the webcam and uses it to 
//update the food buffer which stores information about wall, nest, and food locations

//===========================================================================

//loading in buffers sent by CPU
//store food and foodbackground (to allow for the update to act instantenously) 
layout(binding = 5) buffer foodBuffer { 
	float food [  ];
};
layout(binding = 8) buffer foodBufferBack { 
	float foodBack [  ];
};

//reciving segment for parallelisation
layout(local_size_x= 20, local_size_y=20, local_size_z = 1) in; 

//loading in uniforms
uniform float time;
uniform int W;
uniform int H;
uniform int newFoodX;
uniform int newFoodY;
uniform int heatX;
uniform int heatY;
uniform sampler2DRect webcamData;

 
void main(){

	//loading in positional infomation
	int i = int(gl_GlobalInvocationID.x);								//x					
    int j = int(gl_GlobalInvocationID.y);								//y
	int idx = i+j*W;													//2D->1D

	foodBack[idx]=food[idx];
	foodBack[idx+ W*H]=food[idx + W*H];
	foodBack[idx + 2*W*H]=food[idx + 2*W*H];
	foodBack[idx+3*W*H]+=foodBack[idx+3*W*H];

	if (newFoodX>1 && newFoodY>1){
		if (length(vec2(i-newFoodX,j-newFoodY))<15){
			foodBack[idx]=100.0; 
		}
		if ( i==newFoodX && j==newFoodY){
			foodBack[idx]=-10; 
		}

	}

	if (length(vec2(i-heatX,j-heatY))<60){
		foodBack[idx+3*W*H]+=-0.3;
	}


	
	
}


