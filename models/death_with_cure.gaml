/**
* Name: Flu Virus Project - Comparative Intervention Analysis
* Author: Adaptive AI & Quydx
* Description: SIRD model comparing a 5-day cure (Intervention) vs 10-day recovery (Baseline).
*/

model death_with_cure

global {
    // --- GLOBAL PARAMETERS ---
    int nb_people <- 2147;
    int nb_infected_init <- 10;
    float step <- 10 #mn;
    
    // Disease Parameters
    float proba_infection <- 0.33; 
    float infection_distance <- 5.0 #m;
    int infectious_period_standard <- 10 #days; 
    int infectious_period_cured <- 5 #days; 
    
    // Intervention Toggle
    bool apply_cure_policy <- false; // Set by the Batch Experiment
    
    // --- DEATH PARAMETERS ---
    float death_rate_fixed <- 0.1; // Incremented by Batch
    
    // GIS DATA
    file roads_shapefile <- file("../includes/roads.shp");
    file buildings_shapefile <- file("../includes/buildings.shp");
    geometry shape <- envelope(roads_shapefile);    
    graph road_network;
    
    list<building> companies;
    list<building> homes;
    
    // TRACKING
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
    
    reflex policy_intervention when: apply_cure_policy and every(1 #day) {
        ask (0.01 * nb_people) among people {
            if (self.is_infected and !self.is_isolated) {
                self.is_isolated <- true;
                self.is_cured <- true; // Receives the 5-day recovery benefit
                self.isolation_start_time <- time;
                self.target <- any_location_in(self.my_home); 
            }
        }
    }
}

species building { string type; rgb color <- #gray; aspect geom { draw shape color: color; } }

species people skills:[moving] {        
    bool is_infected <- false;
    bool is_recovered <- false;
    bool is_isolated <- false; 
    bool is_cured <- false;
    
    building my_home;
    building my_work;
    point target;
    float infection_time;
    float isolation_start_time;

    reflex commute {
        if (is_isolated) { return; }
        if (current_date.hour = 8 and target = nil) { target <- any_location_in(my_work); }
        if (current_date.hour = 18 and target = nil) { target <- any_location_in(my_home); }
    }

    reflex move when: target != nil {
        do goto target: target on: road_network;
        if (location = target) { target <- nil; } 
    }

    reflex spread_virus when: is_infected and !is_recovered and !is_isolated {
        ask people at_distance infection_distance {
            if (!self.is_infected and !self.is_recovered) {
                if flip(proba_infection) {
                    self.is_infected <- true;
                    self.infection_time <- time;
                }
            }
        }
    }
    
    reflex recover_or_die when: is_infected and !is_recovered {
        int current_limit <- is_cured ? infectious_period_cured : infectious_period_standard;
        if (time - infection_time) >= current_limit {
            if flip(death_rate_fixed) {
                nb_dead <- nb_dead + 1;
                do die; 
            } else {
                is_infected <- false;
                is_recovered <- true;
                if (is_isolated) { is_isolated <- false; }
            }
        }
    }
    
    aspect circle { draw circle(10) color: is_infected ? #red : (is_recovered ? #yellow : #green); }
}

species road { aspect geom { draw shape color: #black; } }

// --- BATCH EXPERIMENT: DUAL LINE COMPARISON ---
experiment ComparativeSweep type: batch until: (nb_infected = 0 and time > 10#days) 
	keep_seed: true {
    // Parameter 1: The Incremental Death Rate
    parameter "Death Rate" var: death_rate_fixed min: 0.05 max: 1.0 step: 0.1;
    // Parameter 2: The Policy Toggle
    parameter "Apply Cure" var: apply_cure_policy among: [true, false];
init {
        save ["Death_Rate", "Cure_Applied", "Total_Dead"] to: "../results/comparison_results.csv" rewrite: true;
    }

    reflex save_results {
        save [death_rate_fixed, apply_cure_policy, nb_dead] to: "../results/comparison_results.csv" rewrite: false;
    }

    permanent {
        display "Comparison Graph" background: #white {
            chart "Cure Policy vs Baseline" type: xy {
                // Plots results where apply_cure_policy was false
                data "Baseline (10-day)" value: (apply_cure_policy = false) ? {death_rate_fixed, nb_dead} : nil style: line color: #black;
                // Plots results where apply_cure_policy was true
                data "Intervention (5-day Cure)" value: (apply_cure_policy = true) ? {death_rate_fixed, nb_dead} : nil style: line color: #blue;
            }
        }
    }
}