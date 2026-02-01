/**
* Name: Flu Virus Simulation (Project 5)
* Author: Adaptive AI
* Description: SIR model with daily commuting, testing, and isolation policies.
*/

model FluVirusProject

global {
	// --- GLOBAL PARAMETERS ---
	int nb_people <- 3000;
	int nb_infected_init <- 10;
	float step <- 10 #mn; // Time step
	
	// Disease Parameters
	float proba_infection <- 0.33; // 33% chance [cite: 85]
	float infection_distance <- 5.0 #m;
	int infectious_period <- 10 #days; // Fixed 10 days 
	
	// Intervention Parameters
	float daily_testing_rate <- 0.01; // 1% population/day [cite: 90]
	int isolation_duration <- 12 #days; // 12 days isolation [cite: 91]
	
	// --- GIS DATA ---
	file roads_shapefile <- file("../includes/roads.shp");
	file buildings_shapefile <- file("../includes/buildings.shp");
	geometry shape <- envelope(roads_shapefile);	
	graph road_network;
	
	// --- TRACKING VARIABLES ---
	int nb_infected <- 0 update: people count (each.is_infected);
	int nb_recovered <- 0 update: people count (each.is_recovered);
	int nb_susceptible <- 0 update: people count (!each.is_infected and !each.is_recovered);
	
	init {
		create road from: roads_shapefile;
		road_network <- as_edge_graph(road);		
		create building from: buildings_shapefile;
		
		create people number: nb_people {
			// Assign Home and Work 
			my_home <- one_of(building);
			my_work <- one_of(building);
			
			// Start at home
			location <- any_location_in(my_home);
		}
		
		// Patient Zero(s)
		ask nb_infected_init among people {
			is_infected <- true;
			infection_time <- 0.0;
		}
	}
	
	// --- GOVERNMENT INTERVENTION: TESTING [cite: 90] ---
	reflex government_testing when: every(1 #day) {
		// Test 1% of the population randomly
		ask (daily_testing_rate * nb_people) among people {
			if (self.is_infected and !self.is_isolated) {
				self.is_isolated <- true;
				self.isolation_start_time <- time;
				self.target <- any_location_in(self.my_home); // Send home immediately
				self.color <- #blue; // Visual for isolation
			}
		}
	}
}

species people skills:[moving] {		
	// Attributes
	float speed <- (2 + rnd(3)) #km/#h;
	bool is_infected <- false;
	bool is_recovered <- false;
	bool is_isolated <- false;
	
	// Locations
	building my_home;
	building my_work;
	point target;
	
	// Timers
	float infection_time;
	float isolation_start_time;
	
	// Visual Color
	rgb color <- #green;

	// --- DAILY SCHEDULE (Home <-> Work)  ---
	reflex commute {
		// If isolated, do NOT move [cite: 91]
		if (is_isolated) { return; }
		
		// Morning: Go to Work (e.g., 8 AM)
		if (current_date.hour = 8 and target = nil and location distance_to my_work.location > 10#m) {
			target <- any_location_in(my_work);
		}
		
		// Evening: Go Home (e.g., 6 PM)
		if (current_date.hour = 18 and target = nil and location distance_to my_home.location > 10#m) {
			target <- any_location_in(my_home);
		}
	}

	reflex move when: target != nil {
		do goto target: target on: road_network;
		if (location = target) {
			target <- nil;
		} 
	}

	// --- INFECTION LOGIC ---
	reflex spread_virus when: is_infected and !is_recovered {
		// Can only infect if NOT isolated (assuming strict home isolation prevents public contact)
		if (!is_isolated) {
			ask people at_distance infection_distance {
				if (!self.is_infected and !self.is_recovered) {
					if flip(proba_infection) {
						self.is_infected <- true;
						self.infection_time <- time;
						self.color <- #red;
					}
				}
			}
		}
	}
	
	// --- RECOVERY LOGIC  ---
	reflex recover when: is_infected and !is_recovered {
		// Check if 10 days have passed since infection
		if (time - infection_time) >= infectious_period {
			is_infected <- false;
			is_recovered <- true;
			is_isolated <- false; // Released from isolation if recovered
			color <- #yellow;
		}
	}
	
	// --- ISOLATION END LOGIC [cite: 91] ---
	reflex end_isolation when: is_isolated {
		// Check if 12 days have passed since isolation started
		if (time - isolation_start_time) >= isolation_duration {
			is_isolated <- false;
			// If still infected, they might turn red, otherwise yellow
			color <- is_recovered ? #yellow : #red; 
		}
	}
	
	aspect circle {
		draw circle(10) color: color;
	}
}

species road {
	aspect geom { draw shape color: #black; }
}

species building {
	aspect geom { draw shape color: #gray; }
}

experiment main type: gui {
	output {
		monitor "Infected" value: nb_infected;
		monitor "Recovered" value: nb_recovered;
		
		display map {
			species road aspect: geom;
			species building aspect: geom;
			species people aspect: circle;			
		}
	
		display chart_display type: 2d refresh: every(1 #hour) {
			chart "Epidemic Curve" type: series {
				data "Susceptible" value: nb_susceptible color: #green;
				data "Infected" value: nb_infected color: #red;
				data "Recovered" value: nb_recovered color: #yellow;
			}
		}
	}
}