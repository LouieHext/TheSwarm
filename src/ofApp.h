#pragma once

#include "ofMain.h"
#include "ofxGui.h"
#include "ofxKinect.h"

#define W 640*2
#define H 480*2

class ofApp : public ofBaseApp{

	public:
		//oF
		void setup();
		void update();
		void draw();
		void exit();
		//Set up
		void setupAnts();
		void setupShaders();
		void setupParams();
		void setupKinect();
		void generateMap();

		//updates
		void updateMap();
		void updateAnts();
		void updatePheromones();

		//helpers
		void showFPS();
		void keyPressed(int key);

		//shader stuff
		ofShader simulation,diffusion,loader,loaderKinect;
		
		//GPU storage stuff
		struct Ant {
			//needs to be power of 2 aligned in memory
			glm::vec2 pos; //8
			float heading; //12
			bool food; //14
			float time; //18
			glm::vec2 prevPos; //26
			int alignFix; // 28
			float alignFixx; //32
		};

		vector<Ant> ants;
		ofBufferObject antsBuffer, antsBufferClear;
		ofBufferObject pheremonesToFood, pheremonesToNest, pheremonesToFoodBack, pheremonesToNestBack, pheremonesClear,antPos;
		ofBufferObject	foodBuffer,foodBufferBack,foodBufferCopy,foodBufferClear;
		float pheremonesCPU[W*H];
		float foodCPU[W*H*4], foodCPUClear[W*H * 4];

		ofTexture display,displayAlt;

		//gui stuff
		ofxPanel gui;
		ofParameter<float> maxSpeed,turningSpeed,steadiness;
		ofParameter<float> sensorAngle;
		ofParameter<int> sensorDistance, sensorSize;
		ofParameter<float> decayWeight, diffusionWeight,foodDesire, heatDecayWeight;
		ofParameter<int> densitySpeed;
		ofParameter<float> baseMulti, densityMulti;

		ofParameter<float> bumpiness;
		ofParameter<int> farThreshold, nearThreshold;
		ofParameterGroup antSettings, pheromoneSettings,mapSettings,kinectSettings;

		int angle;
		ofxKinect kinect;
};
