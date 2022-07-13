#version 440

//this compute shader updates all the ants and deposits pheromones via 
//stigemrgy methods. The Ants will be guided by previous pheromones of
//all ants. This creates a feedback loop between the micro positions of
//the ants and the macro structure of the pheromones. Which leads to 
//self-organisation in the form of paths.
//The ants have two pheromone types, "toFood" and "toNest". Initially
//the ants spawn near the nest and travel in search of food, leaving
//"toNest" markers as they do. Once they find food they remove some from
//the food source and then turn around and leave "toFood" pheromones.
//Crucially when finding the food they will follow "toFood" and when
//finding the nest they follow "toNest". Pheromones are strongest when 
//an ant has just left a nest/food source and they also diffuse and decay
//this is enough for paths between food and nests to form that gradually
//optimise themselves


//===========================================================================

//loading in particle struct, this matches that of the CPU
//the additional variables are used to make sure that the struct has 16 byte alignment
//which is used assumed in the GPU. (float = 4 byte, bool = 2, int = 2);
struct Particle{
	vec2 pos;			//8 bytes
	float heading;		//12 bytes
	bool food;			//14 bytes
	float time;			//18 bytes
	vec2 prevPos;		//26 bytes
	int alignFix;	    //28 bytes 
	float alignFixx;	//32 bytes
};

//loading in buffers sent by CPU into GPU
layout(std140, binding=0) buffer particleBuffer{
    Particle p[];													//array of particle structs
};
layout(binding = 1) buffer pheremonesToFood { 
	float pheremonesFood [  ];										//array of floats for food pheromones
};
layout(binding = 2) buffer pheremonesToNest { 
	float pheremonesNest [  ];										//array of floats for nest pheromones
};
layout(binding = 5) buffer foodBuffer { 
	float food [  ];												//array of floats for map infomation
};
layout(binding = 8) buffer foodBufferBack { 
	float foodBack [  ];											//array of floats for map infomation
};

layout(local_size_x = 1024, local_size_y = 1, local_size_z = 1) in; //setting up parallisation. 1D, local group size of 1024


//loading in uniforms
//ant params
uniform float maxSpeed;				//ant step size in update function
uniform float turningSpeed;			//ant heading step size in update function
uniform float sensorAngle;			//direction at which they "sense" pheromones
uniform int sensorDistance;			//distance at which they "sense" pheromones
uniform int sensorSize;				//how large of an area thet "sense" (kernel size, 0 = just one pixel)
uniform float foodDesire;			//bias towards food  vs pheromones
uniform int densitySpeed;
uniform float baseMulti;
uniform float densityMulti;

uniform float time;					//used to have positional independet value for randomness
//resolution
uniform int W;						//width
uniform int H;						//height


//helpers
//===========================================================================
//basic GPU random function
//https://stackoverflow.com/questions/4200224/random-noise-functions-for-glsl

float rand(vec2 co){
    return fract(sin(dot(co, vec2(12.9898, 78.233))) * 43758.5453);
}

//===========================================================================


//simulation
//===========================================================================

//rotates a line of length "sensorDistance" at angle theta and returns the coords of the endpoint
vec2 getSensedRegion(Particle particle,float theta) {
    return floor(particle.pos + sensorDistance * vec2(cos(particle.heading + theta),
									                  sin(particle.heading + theta )));
}

//returns the combined value of food and pheromones at the given coords.
//large values are "attractive" and low values "repulsive". The ant food desire
//impacts how much more the ant values food than other ants trails
float getSensedValueFood(vec2 pos) {
    float value = 0;															   //storing value
    for (int i = -sensorSize; i <= sensorSize; i++) {							   //kernel loop
      for (int j = -sensorSize; j <= sensorSize; j++) {
		int idx=int(pos.x) + i + (int(pos.y) + j) * W;							   //2D -> 1D
        value += pheremonesFood[idx]+max(food[idx],0)*foodDesire+min(0,food[idx]) + food[idx+3*W*H]; //negative are walls, split up to use food desire
      }
    }
    return value;
}

//returns the combined value of nest and pheromones at the given coords.
//this is a seperate function as the nest values are in a deeper "layer" of the food array
//and so W*H needs to be added to the idx
float getSensedValueNest(vec2 pos) {
    float value = 0;
    for (int i = -sensorSize; i <= sensorSize; i++) {						      //kernel loop
      for (int j = -sensorSize; j <= sensorSize; j++) {
		int idx=int(pos.x) + i + (int(pos.y) + j) * W;							  //2D -> 1D
        value += pheremonesNest[idx]+min(0,food[idx]) + food[idx+W*H]*foodDesire+food[idx+3*W*H]; //negative are walls, split up to use food desire
      }
    }
    return value;
}


//updates the heading of a particle based on its state and the pheromone maps
//if an ant has food it seeks the nest
//if it does not have food it seeks food
//each ant checks left, forward and right
//and moves in the direction of highest "pheromones" (with some randomness)
float updateHeading(Particle particle) {
    //checking left and right regions.
	float senseLeft,senseForward,senseRight;
	if (particle.food){
	// if has food find the nest
		senseLeft = getSensedValueNest(getSensedRegion(particle,sensorAngle));  //returns the region which we get the value from
		senseForward = getSensedValueNest(getSensedRegion(particle,0.0));
		senseRight = getSensedValueNest(getSensedRegion(particle,-sensorAngle));
    }
	else{
	//if no food find the food
		senseLeft = getSensedValueFood(getSensedRegion(particle,sensorAngle));
		senseForward = getSensedValueFood(getSensedRegion(particle,0.0));
		senseRight = getSensedValueFood(getSensedRegion(particle,-sensorAngle));
	}

//	if (particle.time>1.5*60 && rand(vec2(particle.pos.y,time))>0.95){
//		return particle.heading+(1.5+particle.time*0.02)*turningSpeed*(-0.5+rand(vec2(particle.pos.y,time)) );				   //adding large random to heading
//	}
//
	//moving right
    if (senseRight > max(senseLeft, senseForward)) {													//if right is the highest
      return particle.heading-turningSpeed+0.03*turningSpeed*(-0.5+rand(vec2(particle.pos.y,time)) );   //decreasing heading with some randomness
    }
    //moving left
    else if (senseLeft >max( senseRight, senseForward)) {												//if left is the highest
      return particle.heading + turningSpeed+0.03*turningSpeed*(-0.5+rand(vec2(particle.pos.y,time)) ); //increasing heading with some randomness
    }
	//if approaching a wall
	else if(senseForward<0){
		return particle.heading+3.14/5;																	//sharp turn away 
	}
	//if forward best add random
	//big random
	else if (rand(vec2(particle.pos.x,time))>0.95-particle.time*0.005)  {
	  return particle.heading+(1.5+particle.time*0.01)*turningSpeed*(-0.5+rand(vec2(particle.pos.y,time)) );				   //adding large random to heading
	}
	//small random
	else {
		return particle.heading+0.8*turningSpeed*(-0.5+rand(vec2(particle.pos.y,time)) );			  //adding small random to heading
	} 
}

//standard position update function
//velocity of magnitude "maxSpeed" with direction given by heading
//effectively a jump of "maxSpeed" in direction heading
vec2 updatePos(Particle particle) {
	float speed = maxSpeed * (1.0 + 0.2 * rand(vec2(particle.pos.y,time)));

	if (densitySpeed>0){
		float value = 0;
		int i = int(particle.pos.x);
		int j = int(particle.pos.y);
		for(int ii=-6;ii<=6;ii++){
			for(int jj=-6;jj<=6;jj++){
			    int idx = i+ii+(j+jj)*W;
				value+=pheremonesNest[idx]+pheremonesFood[idx];
				
			}
		}
		speed = maxSpeed*baseMulti + min(value*value*densityMulti*0.01,maxSpeed);
	}
	return particle.pos + speed*vec2(cos(particle.heading),sin(particle.heading));
}

//updates the state of the particle based on its current state and its position in the map
bool updateState(Particle particle){
	int idx=int(particle.pos.x) + int(particle.pos.y) * W;
	if ( particle.food){					 //if the particle has food 
		if (food[idx+W*H]>0){				 //and is in the nest
			return false;					 //"drop" the food and change state to "no food"
		}									 
		return true;						 //if not on nest do nothing
	}										 
	else{									 //if the particle has no food 
		if (food[idx]>0){					 //and is in the food
			for(int ii=-1;ii<=1;ii++){
				for(int jj=-1;jj<=1;jj++){
					int idx = int(particle.pos.x)+ii+(int(particle.pos.y)+jj)*W;
					food[idx] = max(0,food[idx]-10);  //"pickup" the food
					
				}
			}
			return true;					 //and change to state "food"
		}
		return false;						 //if not on food do nothing
	}
}

//applies periodic boundary conditions
//this captures all possiblities without the need for conditionals
// i.e (-5 + W)%W=(W-5)%W=W-5;
// and (W+5+W)%W=(2W+5)%W=5;
vec2 boundaryCheck(vec2 pos) {
    return vec2(mod(pos.x + W,W),mod(pos.y + H,  H));
}

//===========================================================================

void main(){

	Particle particle = p[gl_GlobalInvocationID.x]; 			//loading in particle

//	if (particle.time<35*0.1*30){
	particle.heading=updateHeading(particle);					//updating heading

    vec2 tempPos=updatePos(particle); 							//updating position
    particle.pos=boundaryCheck(tempPos);						//boundary conditions

	bool tempState=particle.food;								//storing updated state
	particle.food=updateState(particle);						//updating state

	particle.time+=0.1;											//updating time since hit a previous target

	if (tempState!=particle.food){								//if particle state has changed,
		particle.heading+=3.14*(0.8+0.5*rand(vec2(particle.pos.x,time)));  //turn the particle around
		particle.time=0.0;										//reset the time
//		food[3*W*H+1]+=1.0;
	}

	int idx=int(particle.pos.x) + int(particle.pos.y) * W;		//translate new position to index

	//if the wall turning failed and particle is inside a wall
	//force it back to its previous position and turn it around
	if (food[idx]<0){											//if inside a wall
		particle.pos=particle.prevPos;							//set back to previous postion
		particle.heading=particle.heading+=3.14*(0.8+0.5*rand(vec2(particle.pos.x,time))); //turn around
	}

	particle.prevPos=particle.pos; //update previous position with current

	//update pheromone maps based on the current state
	//the more recently an ant has reached a nest or food source, the strong the pheromone deposit
	if ( particle.food){  //if has food add to "toFood" map
		pheremonesFood[int(particle.pos.x) + int(particle.pos.y) * W]+=max(0.1,5.0/((particle.time+1.0)*0.1*512.0/W));  //hacky map based on time and resolution 
	}
	else{ //if doesnt have food add to "toNest" map
		pheremonesNest[int(particle.pos.x) + int(particle.pos.y) * W]+=max(0.1,5.0/((particle.time+1.0)*0.1*512.0/W));
	}

	//adding particle position to final layer of the food so they can be displayed
	food[int(particle.pos.x) + int(particle.pos.y) * W+2*W*H]=1;

	//updating particle array
	p[gl_GlobalInvocationID.x]=  particle;

//}
}


