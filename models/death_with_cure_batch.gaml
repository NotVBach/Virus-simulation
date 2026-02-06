/**
* Name: deathwithcurebatch
* Based on the internal empty template. 
* Author: quydx
* Tags: 
*/


model deathwithcurebatch

/* Insert your model definition here */
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
    
    // --- BATCH-CONTROLLED PARAMETERS ---
    float daily_testing_rate <- 0.01; // Variable 1: Testing/Cure intensity
    float death_rate_fixed <- 0.1;   // Variable 2: Virus lethality
    
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
        ask nb_companies among sorted_buildings { type <- "company"; add self to: companies; }
        sorted_buildings <- sorted_buildings - companies;
        ask sorted_buildings { type <- "home"; add self to: homes; }
        
        create people number: nb_people {
            my_home <- one_of(homes);
            my_work <- one_of(companies); 
            location <- any_location_in(my_home);
        }
        ask nb_infected_init among people { is_infected <- true; infection_time <- 0.0; }
    }
    
    // Testing and Cure logic (Section 3.7: Submodels)
    reflex government_intervention when: every(1 #day) {
        ask (daily_testing_rate * nb_people) among people {
            if (self.is_infected and !self.is_isolated) {
                self.is_isolated <- true;
                self.is_cured <- true; 
                self.isolation_start_time <- time;
                self.target <- any_location_in(self.my_home); 
            }
        }
    }
}

species building { string type; aspect geom { draw shape color: #gray; } }

species people skills:[moving] {        
    bool is_infected <- false;
    bool is_recovered <- false;
    bool is_isolated <- false; 
    bool is_cured <- false;
    building my_home; building my_work; point target;
    float infection_time; float isolation_start_time;

    reflex commute {
        if (is_isolated) { return; }
        if (current_date.hour = 8 and target = nil) { target <- any_location_in(my_work); }
        if (current_date.hour = 18 and target = nil) { target <- any_location_in(my_home); }
    }

    reflex move when: target != nil { do goto target: target on: road_network; if (location = target) { target <- nil; } }

    reflex spread_virus when: is_infected and !is_recovered and !is_isolated {
        ask people at_distance infection_distance {
            if (!self.is_infected and !self.is_recovered) { if flip(proba_infection) { self.is_infected <- true; self.infection_time <- time; } }
        }
    }
    
    reflex recover_or_die when: is_infected and !is_recovered {
        int current_limit <- is_cured ? infectious_period_cured : infectious_period_standard;
        if (time - infection_time) >= current_limit {
            if flip(death_rate_fixed) { nb_dead <- nb_dead + 1; do die; }
            else { is_infected <- false; is_recovered <- true; if (is_isolated) { is_isolated <- false; } }
        }
    }
}

species road { aspect geom { draw shape color: #black; } }

// --- BATCH EXPERIMENT: 2D PARAMETER SWEEP ---
experiment "Full Sensitivity Analysis" type: batch until: (nb_infected = 0 and time > 10#days) keep_seed: true {
    
    // Dimension 1: Testing/Cure Rate (Increments from 0% to 80% by 10% each sim)
    parameter "Daily Testing/Cure Rate" var: daily_testing_rate min: 0.0 max: 0.8 step: 0.1;
    
    // Dimension 2: Death Rate (Increments from 0% to 100% by 10% each sim)
    parameter "Death Rate" var: death_rate_fixed min: 0.0 max: 1.0 step: 0.1;

    // Use 'exhaustive' to ensure every combination is tested in a grid

    
    // --- OBSERVATION: DATA COLLECTION [cite: 377] ---
    init {
        save ["Testing_Rate", "Death_Rate", "Total_Dead"] to: "../results/full_2D_sweep.csv" rewrite: true;
    }

    reflex save_results {
        save [daily_testing_rate, death_rate_fixed, nb_dead] to: "../results/full_2D_sweep.csv" rewrite: false;
    }

    permanent {
        display "2D Surface Analysis" background: #white {
            chart "Total Deaths Grid" type: xy {
                // This will plot points for every combination
                data "Death Count" value: {death_rate_fixed, nb_dead} 
                     color: (daily_testing_rate * 255) as rgb // Color shifts based on testing rate
                     style: dot;
            }
        }
    }
}
