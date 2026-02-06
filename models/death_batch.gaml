/**
* Name: Flu Virus Project - Deterministic Death Increment
* Author: Quydx & Gemini
* Description: SIRD model using an Exhaustive Batch to increase death rates by 10% per simulation.
*/

model deathbatch_linear

global {
	// --- GLOBAL PARAMETERS ---
	int nb_people <- 2147;
	int nb_infected_init <- 10;
	float step <- 10 #mn;
	
	// Disease Parameters
	float proba_infection <- 0.33; 
	float infection_distance <- 5.0 #m;
	int infectious_period <- 10 #days; 
	
	// --- DETERMINISTIC DEATH PARAMETERS ---
	// This value is controlled by the Batch Experiment (Section 3.7: Submodels)
	float death_rate_fixed <- 0.1; 
	
	// Intervention Parameters
	float daily_testing_rate <- 0.01; 
	int isolation_duration <- 10 #days; 
	
	// --- GIS DATA ---
	file roads_shapefile <- file("../includes/roads.shp");
	file buildings_shapefile <- file("../includes/buildings.shp");
	geometry shape <- envelope(roads_shapefile);	
	graph road_network;
	
	list<building> companies;
	list<building> homes;
	
	// --- TRACKING ---
	int nb_infected <- 0 update: people count (each.is_infected);
	int nb_dead <- 0; 
	
	init {
		create road from: roads_shapefile;
		road_network <- as_edge_graph(road);		
		create building from: buildings_shapefile;
		
		list<building> sorted_buildings <- building sort_by (-1 * each.shape.area);
		int nb_companies <- int(length(sorted_buildings) * 0.2);
		ask nb_companies among sorted_buildings {
			type <- "company";
			color <- #blue;
			add self to: companies;
		}
		sorted_buildings <- sorted_buildings - companies;
		
		ask sorted_buildings {
			type <- "home";
			color <- #green;
			add self to: homes;
		}
		
		list<building> available_homes <- copy(homes);
		int people_created <- 0;
		
		loop while: people_created < nb_people {
			int family_size <- rnd(3, 6);
			if (people_created + family_size > nb_people) { family_size <- nb_people - people_created; }
			
			building assigned_home <- one_of(available_homes);
			if (assigned_home = nil) { assigned_home <- one_of(homes); } 
			else { remove assigned_home from: available_homes; }
			
			create people number: family_size {
				my_home <- assigned_home;
				my_work <- one_of(companies); 
				location <- any_location_in(my_home);
			}
			people_created <- people_created + family_size;
		}
		
		ask nb_infected_init among people {
			is_infected <- true;
			infection_time <- 0.0;
			color <- #red;
		}
	}
	
	reflex government_testing when: every(1 #day) {
		ask (daily_testing_rate * nb_people) among people {
			if (self.is_infected and !self.is_isolated) {
				self.is_isolated <- true;
				self.isolation_start_time <- time;
				self.target <- any_location_in(self.my_home); 
				self.color <- #blue; 
			}
		}
	}
}

species building {
	string type; 
	rgb color <- #gray;
	aspect geom { draw shape color: color; }
}

species people skills:[moving] {		
	bool is_infected <- false;
	bool is_recovered <- false;
	bool is_isolated <- false; 
	
	building my_home;
	building my_work;
	point target;
	
	float infection_time;
	float isolation_start_time;
	rgb color <- #green;

	reflex commute {
		if (is_isolated) { return; }
		if (current_date.hour = 8 and target = nil and location distance_to my_work.location > 10#m) {
			target <- any_location_in(my_work);
		}
		if (current_date.hour = 18 and target = nil and location distance_to my_home.location > 10#m) {
			target <- any_location_in(my_home);
		}
	}

	reflex move when: target != nil {
		do goto target: target on: road_network;
		if (location = target) { target <- nil; } 
	}

	reflex spread_virus when: is_infected and !is_recovered {
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
	
	// --- SUBMODEL: RECOVER OR DIE (Section 3.7) ---
	reflex recover_or_die when: is_infected and !is_recovered {
		if (time - infection_time) >= infectious_period {
			
			// DETERMINISTIC LOGIC: No flip. 
			// The global death_rate_fixed is used as the threshold.
			if flip(death_rate_fixed) {
				nb_dead <- nb_dead + 1;
				do die; 
			} else {
				is_infected <- false;
				is_recovered <- true;
				color <- #yellow;
				if (is_isolated) { is_isolated <- false; }
			}
		}
	}
	
	reflex end_isolation when: is_isolated {
		if (time - isolation_start_time) >= isolation_duration {
			is_isolated <- false;
			if (is_infected) { color <- #red; }
		}
	}
	
	aspect circle { draw circle(10) color: color; }
}

species road {
	aspect geom { draw shape color: #black; }
}

// --- BATCH EXPERIMENT: 10% INCREMENTAL SWEEP ---
//
experiment "Ascending Death Sweep" type: batch until: (nb_infected = 0 and time > 10#days) {
    
    // Starts at 0.1, ends at 1.0, increases by 0.1 (10%) each simulation
    parameter "Fixed Death Rate" var: death_rate_fixed min: 0.05 max: 1.0 step: 0.1;

    // 'Exhaustive' ensures simulation 1 = 0.1, simulation 2 = 0.2, etc.
   
    permanent {
        display "Result Analysis" background: #white {
            chart "Death Rate vs Total Fatalities" type: xy {
                data "Total Dead" value: {death_rate_fixed, nb_dead} style: line color: #red;
            }
        }
        
        
    }
}