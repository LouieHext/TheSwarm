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
uniform int W;
uniform int H;
uniform sampler2DRect webcamData;
uniform  float thresholdGreen;
uniform  float thresholdYellow;

//Colour conversion functions from - https://www.chilliant.com/rgb2hsv.html
//===========================================================================
 float Epsilon = 1e-10;
 vec3 RGBtoHCV( vec3 RGB)
  {
    // Based on work by Sam Hocevar and Emil Persson
    vec4 P = (RGB.g < RGB.b) ? vec4(RGB.bg, -1.0 , 2.0/3.0) : vec4(RGB.gb, 0.0 , -1.0/3.0);
    vec4 Q = (RGB.r < P.x) ? vec4(P.xyw, RGB.r) : vec4(RGB.r, P.yzx);
    float C = Q.x - min(Q.w, Q.y);
    float H = abs((Q.w - Q.y) / (6 * C + Epsilon) + Q.z);
    return vec3(H, C, Q.x);
  }

vec3 HUEtoRGB(float H)
  {
    float R = abs(H * 6 - 3) - 1;
    float G = 2 - abs(H * 6 - 2);
    float B = 2 - abs(H * 6 - 4);
    return clamp(vec3(R,G,B), 0, 1);
  }
vec3 HSLtoRGB(vec3 HSL)
  {	
	HSL=vec3(min(HSL.x,1.0),min(HSL.y,1.0),min(HSL.z,1.0));
    vec3 RGB = HUEtoRGB(HSL.x);
    float C = (1 - abs(2 * HSL.z - 1)) * HSL.y;
    return (RGB - 0.5) * C + HSL.z;
  }

 vec3 RGBtoHSL(vec3 RGB)
  {
    vec3 HCV = RGBtoHCV(RGB);
    float L = HCV.z - HCV.y * 0.5;
    float S = HCV.y / (1 - abs(L * 2 - 1) + Epsilon);
    return vec3(HCV.x, S, L);
  }

 //helpers
//===========================================================================

  //boost saturation and brightness
vec4 boost(vec4 col){
	vec3 colHSL=RGBtoHSL(vec3(col.x,col.y,col.z));		//get HSL
	vec3 boosted=HSLtoRGB(colHSL+vec3(0.0 ,0.1,0.00	));  //boost HSL and send back to RGB
	return vec4(vec3(boosted),1.0);
}


 vec4 improveColour(int i, int j){
	vec4 newCol;
	int count=0;
	for (int ii=-10;ii<=10;ii++){							//kerel loop
		for(int jj=-10;jj<=10;jj++){
			vec4 col=texture(webcamData,vec2(i+ii,j+jj));
			col=boost(col);								//more saturation and lightness
			newCol+=col;								//summation of kernel
			count++;
		}
	}
	return newCol/count;								//averaging


 }
 //===========================================================================

void main(){

	//loading in positional infomation
	int i = int(gl_GlobalInvocationID.x);								//x					
    int j = int(gl_GlobalInvocationID.y);								//y
	int idx = i+j*W;													//2D->1D

	//setting target colours
	vec4 wallCol = vec4(0.1,0.1,0.1,1.0);								//black
	vec4 foodCol = vec4(0.1 ,0.9,0.1 ,1.0);							//green
	vec4 nestCol = vec4(0.8,0.8,0.1 ,1.0);								//yellow

	//blurring and boosting colour at position
	vec4 newCol=improveColour(i,j);

	//updating food background map
	//we update the background map to avoid any issues of sequencing
	//the code does not run every pixel at the same time and so one cells update
	//can influence another cells update, this is bad.
	//so we update a background layer and then when all updates are done
	//we copy the background layer into the main layer (this happens in CPU code)

	if (distance(newCol,wallCol)<0.2){									//if webcam data is wallCol, make a wall
		foodBack[idx]=-10000.0;											//wall is negative food and stored in zeroth food layer
	}		
	else if (distance(newCol,nestCol)<thresholdYellow && food[idx]>=0.0){								//if webcam data is nestCol, make a nest
		foodBack[idx+W*H]=1000.0;										//nests are positive values stored in the first food layer
	}

	else if (distance(newCol,foodCol)<thresholdGreen && food[idx]==0.0 ){		    //if webcam data is foodCol and not currently food move to next check 
																		//we only want to make new food if new area, not refresh previous food 
		float neighbours=0.0;									       //so we check all the neighbouring values for food
		for (int ii=-40;ii<=40;ii++){ //kernel loop 
			for(int jj=-40;jj<=40;jj++){
				neighbours+=min(1.0, max(0.0,food[i+ii+(j+jj)*W]) );	//the max forces only positive values (dont want negative wall values)
			}														    //the min forces value to be one, we only check if food not how much
		}															    //this avoids conditional branches (bad in GPU code)
		
		if (neighbours<1){												//if no neighbours, must be new food so add  it in
			foodBack[idx]=100.0; 
		}
	}
	else if (food[idx]>0 ){												//if already food keep it as is
		foodBack[idx]=food[idx];
	}
	else{																//if not detected make sure old nests are removed 
		foodBack[idx+W*H]=0.0;
	}
}


