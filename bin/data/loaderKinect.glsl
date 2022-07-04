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

layout(rgba8,binding=7)  uniform writeonly image2D pheremoneDisplay; //output to buffer

//reciving segment for parallelisation
layout(local_size_x= 20, local_size_y=20, local_size_z = 1) in; 

//loading in uniforms
uniform int farThreshold;
uniform int nearThreshold;
uniform int depthW;
uniform int depthH;
uniform sampler2DRect kinectData;
uniform int W;
uniform int H;


 
void main(){

	//loading in positional infomation
	int x = int(gl_GlobalInvocationID.x);								//x					
    int y = int(gl_GlobalInvocationID.y);								//y

	int i = int((float(x)/float(depthW))*W);
	int j = int((float(y)/float(depthH))*H);
	int idx = i+j*W;													//2D->1D

	vec4 depthTexture=texture(kinectData,vec2(x,y));
//	imageStore(pheremoneDisplay,ivec2(i,j),depthTexture);
	int depthColour = int(0.33*(depthTexture.x+depthTexture.y+depthTexture.z)*255);
	if (depthColour>farThreshold && depthColour<nearThreshold){
		foodBack[idx+3*W*H]+=-0.3;
	}


	
	
}


