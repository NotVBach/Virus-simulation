/**
* Name: Flu Virus Project - Complex Buildings
* Author: Adaptive AI
* Description: SIR model with Companies, Homes, and Hospitals (Capacity constrained).
*/

model FluVirusProject

global {
	// --- GLOBAL PARAMETERS ---
	int nb_people <- 3000;
	int nb_infected_init <- 10;
	float step <- 10 #mn;
	
	// Disease Parameters
	float proba_infection <- 0.33; 
	float infection_distance <- 5.0 #m;
	int infectious_period <- 10 #days; 
	
	// Intervention Parameters
	float daily_testing_rate <- 0.01; 
	int isolation_duration <- 12 #days;
	int total_hospital_capacity <- int(nb_people / 10); // 10% of population
	
	// --- GIS DATA ---
	file roads_shapefile <- file("../includes/roads.shp");
	file buildings_shapefile <- file("../includes/buildings.shp");
	geometry shape <- envelope(roads_shapefile);	
	graph road_network;
	
	// --- BUILDING LISTS ---
	list<building> hospitals;
	list<building> companies;
	list<building> homes;
	
	// --- TRACKING ---
	int nb_infected <- 0 update: people count (each.is_infected);
	int nb_hospitalized <- 0 update: people count (each.is_hospitalized);
	int nb_isolated_home <- 0 update: people count (each.is_isolated);
	
	init {
		create road from: roads_shapefile;
		road_network <- as_edge_graph(road);		
		create building from: buildings_shapefile;
		
		// --- BUILDING ASSIGNMENT ---
		// 1. Sort buildings by area to pick the largest for Hospitals/Companies
		list<building> sorted_buildings <- building sort_by (-1 * each.shape.area);
		
		// 2. Assign Hospitals (Top 2 largest for example, or until capacity met)
		// We just pick the largest one to be the main hospital
		ask first(sorted_buildings) {
			type <- "hospital";
			color <- #white;
			capacity <- total_hospital_capacity;
			add self to: hospitals;
		}
		remove first(sorted_buildings) from: sorted_buildings;
		
		// 3. Assign Companies (Next 20% of buildings)
		int nb_companies <- int(length(sorted_buildings) * 0.2);
		ask nb_companies among sorted_buildings {
			type <- "company";
			color <- #blue;
			add self to: companies;
		}
		sorted_buildings <- sorted_buildings - companies;
		
		// 4. Assign Homes (The rest)
		ask sorted_buildings {
			type <- "home";
			color <- #green;
			add self to: homes;
		}
		
		// --- PEOPLE GENERATION ---
		// We generate families to fill homes with 3-6 people
		list<building> available_homes <- copy(homes);
		int people_created <- 0;
		
		loop while: people_created < nb_people {
			// Pick a random home size (3 to 6)
			int family_size <- rnd(3, 6);
			// Check if we exceed total population
			if (people_created + family_size > nb_people) { family_size <- nb_people - people_created; }
			
			// Pick a home
			building assigned_home <- one_of(available_homes);
			if (assigned_home = nil) { assigned_home <- one_of(homes); } // Fallback if ran out
			else { remove assigned_home from: available_homes; }
			
			create people number: family_size {
				my_home <- assigned_home;
				// Assign a random company as workplace
				my_work <- one_of(companies); 
				
				location <- any_location_in(my_home);
			}
			people_created <- people_created + family_size;
		}
		
		// Patient Zero
		ask nb_infected_init among people {
			is_infected <- true;
			infection_time <- 0.0;
			color <- #red;
		}
	}
	
	// --- GOVERNMENT INTERVENTION ---
	reflex government_testing when: every(1 #day) {
		ask (daily_testing_rate * nb_people) among people {
			if (self.is_infected and !self.is_isolated and !self.is_hospitalized) {
				
				// 1. Try to find a hospital with space
				building target_hospital <- one_of(hospitals where (length(each.occupants) < each.capacity));
				
				if (target_hospital != nil) {
					// TRANSFER TO HOSPITAL
					self.is_hospitalized <- true;
					self.my_hospital <- target_hospital;
					self.location <- any_location_in(target_hospital);
					self.target <- nil; // Stop moving
					ask target_hospital { add myself to: occupants; }
					self.color <- #magenta;
				} else {
					// HOSPITAL FULL -> LOCKDOWN AT HOME
					self.is_isolated <- true;
					self.isolation_start_time <- time;
					self.target <- any_location_in(self.my_home);
					self.color <- #blue; 
				}
			}
		}
	}
}

species building {
	string type; // "home", "company", "hospital"
	rgb color <- #gray;
	int capacity <- 0; // Only used for hospitals
	list<people> occupants;
	
	aspect geom {
		draw shape color: color;
		if (type = "hospital") {
			draw cross(15, 5) color: #red at: location + {0,0,2}; // Red cross on roof
		}
	}
}

species people skills:[moving] {		
	// Status
	bool is_infected <- false;
	bool is_recovered <- false;
	bool is_isolated <- false; // Home lockdown
	bool is_hospitalized <- false; // In hospital
	
	// Locations
	building my_home;
	building my_work;
	building my_hospital;
	point target;
	
	// Timers
	float infection_time;
	float isolation_start_time;
	
	rgb color <- #green;

	// --- MOVEMENT SCHEDULE ---
	reflex commute {
		// If hospitalized or isolated, DO NOT MOVE
		if (is_hospitalized or is_isolated) { return; }
		
		// Work Start (8 AM)
		if (current_date.hour = 8 and target = nil and location distance_to my_work.location > 10#m) {
			target <- any_location_in(my_work);
		}
		
		// Work End (6 PM)
		if (current_date.hour = 18 and target = nil and location distance_to my_home.location > 10#m) {
			target <- any_location_in(my_home);
		}
	}

	reflex move when: target != nil {
		do goto target: target on: road_network;
		if (location = target) { target <- nil; } 
	}

	// --- INFECTION ---
	reflex spread_virus when: is_infected and !is_recovered {
		// Hospitalized/Isolated people do NOT spread to the general public 
		// (Assuming perfect isolation for simulation simplicity)
		if (!is_isolated and !is_hospitalized) {
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
	
	// --- RECOVERY ---
	reflex recover when: is_infected and !is_recovered {
		if (time - infection_time) >= infectious_period {
			is_infected <- false;
			is_recovered <- true;
			color <- #yellow;
			
			// If Hospitalized, discharge
			if (is_hospitalized) {
				is_hospitalized <- false;
				ask my_hospital { remove myself from: occupants; }
				my_hospital <- nil;
				target <- any_location_in(my_home); // Go back home
			}
			
			// If Isolated, release
			if (is_isolated) {
				is_isolated <- false;
			}
		}
	}
	
	aspect circle {
		draw circle(10) color: color;
	}
}

species road {
	aspect geom { draw shape color: #black; }
}

experiment main type: gui {
	output {
		// Monitors
		monitor "Active Infections" value: nb_infected;
		monitor "Hospitalized" value: nb_hospitalized;
		monitor "Home Isolation" value: nb_isolated_home;
		monitor "Available Hospital Beds" value: (total_hospital_capacity - nb_hospitalized);
		
		display map {
			species road aspect: geom;
			species building aspect: geom;
			species people aspect: circle;			
		}
	
		display chart_display type: 2d refresh: every(1 #hour) {
			chart "Hospital Strain" type: series {
				data "Hospitalized" value: nb_hospitalized color: #magenta;
				data "Home Isolation" value: nb_isolated_home color: #blue;
				data "Total Infected" value: nb_infected color: #red;
			}
		}
	}
}