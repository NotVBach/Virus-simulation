/**
* Name: Flu Virus Project - Hospital Cure & Lethality Analysis
* Author: quydx
* Description: SIRD model with Hospital-based 5-day cure and 10-day standard recovery.
* Protocol: Follows the ODD standard[cite: 261].
*/

model deathbatch_hospital

global {
	// --- GLOBAL PARAMETERS (Section 3.2) [cite: 283] ---
	int nb_people <- 3000;
	int nb_infected_init <- 10;
	float step <- 10 #mn;
	
	// Disease Parameters [cite: 310]
	float proba_infection <- 0.33; 
	float infection_distance <- 5.0 #m;
	int infectious_period_standard <- 10 #days; 
	int infectious_period_hospital <- 5 #days; // Accelerated cure in hospital
	
	// --- INTERVENTION PARAMETERS ---
	float daily_testing_rate <- 0.01; 
	int isolation_duration <- 12 #days;
	int hospital_capacity_per_unit <- 30; // Capacity per hospital building
	
	// --- BATCH CONTROLLED PARAMETERS ---
	float death_rate_fixed <- 0.1; // Fixed 10% dying chance [cite: 369]
	int nb_hospitals_available <- 1; // Swept from 1 to 10 in batch
	
	// --- GIS DATA (Section 3.6) [cite: 397] ---
	file roads_shapefile <- file("../includes/roads.shp");
	file buildings_shapefile <- file("../includes/buildings.shp");
	geometry shape <- envelope(roads_shapefile);	
	graph road_network;
	
	list<building> hospitals;
	list<building> companies;
	list<building> homes;
	
	// --- TRACKING (Section 3.4.11) [cite: 377] ---
	int nb_infected <- 0 update: people count (each.is_infected);
	int nb_dead <- 0; 
	int nb_hospitalized <- 0 update: people count (each.is_hospitalized);
	
	init {
		create road from: roads_shapefile;
		road_network <- as_edge_graph(road);		
		create building from: buildings_shapefile;
		
		// Sort buildings to assign types [cite: 462]
		list<building> sorted_buildings <- building sort_by (-1 * each.shape.area);
		
		// 1. Assign Hospitals based on batch parameter
		ask nb_hospitals_available among sorted_buildings {
			type <- "hospital";
			color <- #white;
			capacity <- hospital_capacity_per_unit;
			add self to: hospitals;
		}
		sorted_buildings <- sorted_buildings - hospitals;
		
		// 2. Assign Companies (20%)
		int nb_companies <- int(length(sorted_buildings) * 0.2);
		ask nb_companies among sorted_buildings {
			type <- "company";
			color <- #blue;
			add self to: companies;
		}
		sorted_buildings <- sorted_buildings - companies;
		
		// 3. Assign Homes
		ask sorted_buildings {
			type <- "home";
			color <- #green;
			add self to: homes;
		}
		
		// People Generation [cite: 298]
		create people number: nb_people {
			my_home <- one_of(homes);
			my_work <- one_of(companies); 
			location <- any_location_in(my_home);
		}
		
		ask nb_infected_init among people {
			is_infected <- true;
			infection_time <- 0.0;
		}
	}
	
	// --- SUBMODEL: HOSPITALIZATION & CURE (Section 3.7) [cite: 411] ---
	reflex government_intervention when: every(1 #day) {
		ask (daily_testing_rate * nb_people) among people {
			if (self.is_infected and !self.is_isolated and !self.is_hospitalized) {
				building target_hospital <- one_of(hospitals where (length(each.occupants) < each.capacity));
				
				if (target_hospital != nil) {
					self.is_hospitalized <- true;
					self.my_hospital <- target_hospital;
					self.location <- any_location_in(target_hospital);
					ask target_hospital { add myself to: occupants; }
				} else {
					self.is_isolated <- true;
					self.isolation_start_time <- time;
					self.target <- any_location_in(self.my_home);
				}
			}
		}
	}
}

species building {
	string type; rgb color <- #gray; int capacity <- 0; list<people> occupants;
	aspect geom { draw shape color: color; }
}

species people skills:[moving] {		
	bool is_infected <- false;
	bool is_recovered <- false;
	bool is_isolated <- false; 
	bool is_hospitalized <- false;
	
	building my_home; building my_work; building my_hospital;
	point target; float infection_time; float isolation_start_time;

	reflex commute {
		if (is_isolated or is_hospitalized) { return; }
		if (current_date.hour = 8 and target = nil) { target <- any_location_in(my_work); }
		if (current_date.hour = 18 and target = nil) { target <- any_location_in(my_home); }
	}

	reflex move when: target != nil {
		do goto target: target on: road_network;
		if (location = target) { target <- nil; } 
	}

	reflex spread_virus when: is_infected and !is_recovered and !is_isolated and !is_hospitalized {
		ask people at_distance infection_distance {
			if (!self.is_infected and !self.is_recovered) {
				if flip(proba_infection) { self.is_infected <- true; self.infection_time <- time; }
			}
		}
	}
	
	// --- RECOVER OR DIE SUBMODEL [cite: 414] ---
	reflex recover_or_die when: is_infected and !is_recovered {
		// Use 5 days if hospitalized, 10 days otherwise
		int current_limit <- is_hospitalized ? infectious_period_hospital : infectious_period_standard;
		
		if (time - infection_time) >= current_limit {
			if flip(death_rate_fixed) {
				nb_dead <- nb_dead + 1;
				if (is_hospitalized) { ask my_hospital { remove myself from: occupants; } }
				do die; 
			} else {
				is_infected <- false;
				is_recovered <- true;
				if (is_hospitalized) { 
					is_hospitalized <- false; 
					ask my_hospital { remove myself from: occupants; }
					my_hospital <- nil;
				}
				is_isolated <- false;
			}
		}
	}
	aspect circle { draw circle(10) color: is_infected ? #red : (is_recovered ? #yellow : #green); }
}

species road { aspect geom { draw shape color: #black; } }

// --- BATCH EXPERIMENT: HOSPITAL SENSITIVITY [cite: 426, 491] ---
experiment "Hospital Cure Analysis" type: batch until: (nb_infected = 0 and time > 10#days) keep_seed: true {
    
    // Increment number of hospitals from 1 to 10
    parameter "Hospitals Available" var: nb_hospitals_available min: 0 max: 10 step: 1;
   
    
    init {
        save ["Hospital_Count", "Total_Deaths"] to: "../results/hospital_cure_results.csv" rewrite: true;
    }

    reflex save_results {
        save [nb_hospitals_available, nb_dead] to: "../results/hospital_cure_results.csv" rewrite: false;
    }

    permanent {
        display "Death Statistics" background: #white {
            chart "Impact of Hospital Availability on Deaths" type: xy {
                data "Total Dead" value: {nb_hospitals_available, nb_dead} style: line color: #red;
            }
        }
    }
}