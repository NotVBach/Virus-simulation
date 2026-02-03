/**
* Name: Flu Virus Project - Home Isolation Only
* Author: Quydx
* Description: SIRD model with NO Hospitals. Strict Home Isolation policy.
*/

model deathbatch

global {
	// --- GLOBAL PARAMETERS ---
	int nb_people <- 2147;
	int nb_infected_init <- 10;
	float step <- 10 #mn;
	
	// Disease Parameters
	float proba_infection <- 0.33; 
	float infection_distance <- 5.0 #m;
	int infectious_period <- 10 #days; 
	
	// --- DEATH PARAMETERS ---
	float ratio_high_risk_population <- 0.0; 
	float death_rate_low <- 0.01; 
	float death_rate_high <- 0.70; 
	
	// Intervention Parameters
	float daily_testing_rate <- 0.01; // 1% testing per day
	int isolation_duration <- 10 #days; // CHANGED: 10 days strict lockdown
	
	// --- GIS DATA ---
	file roads_shapefile <- file("../includes/roads.shp");
	file buildings_shapefile <- file("../includes/buildings.shp");
	geometry shape <- envelope(roads_shapefile);	
	graph road_network;
	
	list<building> companies;
	list<building> homes;
	
	// --- TRACKING ---
	int nb_infected <- 0 update: people count (each.is_infected);
	int nb_isolated_home <- 0 update: people count (each.is_isolated);
	int nb_dead <- 0; 
	
	init {
		create road from: roads_shapefile;
		road_network <- as_edge_graph(road);		
		create building from: buildings_shapefile;
		
		// 1. Sort buildings by size
		list<building> sorted_buildings <- building sort_by (-1 * each.shape.area);
		
		// 2. Assign Companies (Top 20% of buildings)
		int nb_companies <- int(length(sorted_buildings) * 0.2);
		ask nb_companies among sorted_buildings {
			type <- "company";
			color <- #blue;
			add self to: companies;
		}
		sorted_buildings <- sorted_buildings - companies;
		
		// 3. Assign Homes (The rest)
		ask sorted_buildings {
			type <- "home";
			color <- #green;
			add self to: homes;
		}
		
		// --- PEOPLE GENERATION ---
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
				
				// Death Rate Assignment
				if flip(ratio_high_risk_population) {
					death_prob <- death_rate_high; 
				} else {
					death_prob <- death_rate_low; 
				}
			}
			people_created <- people_created + family_size;
		}
		
		ask nb_infected_init among people {
			is_infected <- true;
			infection_time <- 0.0;
			color <- #red;
		}
	}
	
	// --- GOVERNMENT POLICY: TEST & ISOLATE ---
	reflex government_testing when: every(1 #day) {
		ask (daily_testing_rate * nb_people) among people {
			// If Infected AND not already isolated
			if (self.is_infected and !self.is_isolated) {
				// FORCE HOME ISOLATION
				self.is_isolated <- true;
				self.isolation_start_time <- time;
				self.target <- any_location_in(self.my_home); // Go home immediately
				self.color <- #blue; 
			}
		}
	}
}

species building {
	string type; 
	rgb color <- #gray;
	
	aspect geom {
		draw shape color: color;
	}
}

species people skills:[moving] {		
	bool is_infected <- false;
	bool is_recovered <- false;
	bool is_isolated <- false; 
	
	float death_prob; 
	
	building my_home;
	building my_work;
	point target;
	
	float infection_time;
	float isolation_start_time;
	rgb color <- #green;

	reflex commute {
		// If Isolated, STAY HOME
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
		// Isolated people do not spread virus (Assuming 100% compliance)
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
	
	// --- RECOVER OR DIE LOGIC ---
	reflex recover_or_die when: is_infected and !is_recovered {
		if (time - infection_time) >= infectious_period {
			// Roll dice for death
			if flip(death_prob) {
				// DEATH CASE
				nb_dead <- nb_dead + 1;
				do die; 
				
			} else {
				// RECOVERY CASE
				is_infected <- false;
				is_recovered <- true;
				color <- #yellow;
				
				// Release from isolation if recovered
				if (is_isolated) { is_isolated <- false; }
			}
		}
	}
	
	// --- END ISOLATION LOGIC ---
	// If they are still isolated but the 10 days have passed (and they didn't die/recover yet)
	reflex end_isolation when: is_isolated {
		if (time - isolation_start_time) >= isolation_duration {
			is_isolated <- false;
			// Reset color if they are still infected
			if (is_infected) { color <- #red; }
		}
	}
	
	aspect circle { draw circle(10) color: color; }
}

species road {
	aspect geom { draw shape color: #black; }
}

// --- GUI EXPERIMENT ---
experiment main type: gui {
	output {
		monitor "Total Deaths" value: nb_dead;
		monitor "Active Infections" value: nb_infected;
		monitor "Home Isolation" value: nb_isolated_home;
		
		display map {
			species road aspect: geom;
			species building aspect: geom;
			species people aspect: circle;			
		}
	
		display chart_display type: 2d refresh: every(1 #hour) {
			chart "Population Status" type: series {
				data "Dead" value: nb_dead color: #black;
				data "Infected" value: nb_infected color: #red;
				data "Recovered" value: (people count each.is_recovered) color: #yellow;
				data "Isolated" value: nb_isolated_home color: #blue style: line;
			}
		}
	}
}

// --- BATCH EXPERIMENT ---
// --- BATCH EXPERIMENT (DECREASING) ---
experiment GeneticDeathOptimization type: batch until: (nb_infected = 0 and time > 10#days) {
    
    // DECREASING: Max 1.0 -> Min 0.01
    // Note: Genetic algorithms don't strictly follow order, but if you use 
    // a standard parameter sweep (non-genetic), this ensures the range is covered.
    parameter "Ratio of High Risk Population" 
        var: ratio_high_risk_population 
        min: 0.01 max: 1.0 step: 0.01;

    // Use the genetic method if you want to FIND the peak
    // Or remove 'method genetic' if you want to simply simulate 100 steps in order.
    method genetic maximize: nb_dead 
        pop_dim: 10             
        crossover_prob: 0.7     
        mutation_prob: 0.1      
        nb_prelim_gen: 1        
        max_gen: 20;            
    
    init {
        save ["Generation", "Best_Risk_Ratio", "Max_Deaths"] 
           to: "genetic_death_results.csv" 
           rewrite: true;
    }

    reflex save_results {
        save [ratio_high_risk_population, nb_dead] 
           to: "genetic_death_results.csv" 
           rewrite: false;
    }

    permanent {
        display GeneticProgress background: #white {
            chart "Genetic Optimization" type: series {
                data "Deaths" value: nb_dead style: dot color: #red;
            }
        }
    }
}