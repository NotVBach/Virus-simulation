model lockdown_with_death

global {
	// --- GLOBAL PARAMETERS ---
	int nb_people <- 3000;
	int nb_infected_init <- 10;
	float step <- 10 #mn;
	
	// Disease & Intervention Parameters
	float proba_infection <- 0.33; 
	float infection_distance <- 5.0 #m;
	int infectious_period <- 10 #days; 
	float death_rate <- 0.1; 
	float daily_testing_rate <- 0.01; 
	int district_lockdown_duration <- 14 #days; // Duration of the barrier
	
	// GIS DATA
	file roads_shapefile <- file("../includes/roads.shp");
	file buildings_shapefile <- file("../includes/buildings.shp");
	geometry shape <- envelope(roads_shapefile);	
	graph road_network;
	
	// TRACKING
	int nb_infectible <- 0 update: people count (!each.is_infected and !each.is_recovered);
	int nb_infected <- 0 update: people count (each.is_infected);
	int nb_recovered <- 0 update: people count (each.is_recovered);
	int nb_dead <- 0; 
	int nb_districts_locked <- 0 update: district count (each.is_locked_down);
	
	init {
		create road from: roads_shapefile;
		road_network <- as_edge_graph(road);		
		create building from: buildings_shapefile;
		create people number: nb_people {
			my_home <- one_of(building);
			my_work <- one_of(building);
			location <- any_location_in(my_home);
			my_district <- district closest_to self; 
		}
		ask nb_infected_init among people { is_infected <- true; infection_time <- 0.0; }
	}
	
	reflex government_intervention when: every(1 #day) {
		ask (daily_testing_rate * nb_people) among people {
			if (self.is_infected) {
				if (!self.is_isolated) {
					self.is_isolated <- true;
					self.isolation_start_time <- time;
					self.target <- any_location_in(self.my_home);
				}
				if (self.my_district != nil) {
					ask self.my_district {
						if (!self.is_locked_down) {
							self.is_locked_down <- true;
							self.lockdown_start_time <- time; // Start the 14-day clock
						}
					}
				}
			}
		}
	}
}

// --- SPATIAL ENTITY: DISTRICTS ---
grid district width: 5 height: 4 {
	bool is_locked_down <- false;
	float lockdown_start_time;
	
	// TRIGGER: This removes the lockdown barrier automatically
	reflex update_lockdown when: is_locked_down {
		if (time - lockdown_start_time) >= district_lockdown_duration {
			is_locked_down <- false; // The 'barrier' is removed here
		}
	}
	
	aspect base {
		// The red overlay disappears when is_locked_down is false
		draw shape color: is_locked_down ? rgb(255, 0, 0, 80) : rgb(255, 255, 255, 0) border: #black;
	}
}

species people skills:[moving] {		
	bool is_infected <- false;
	bool is_recovered <- false;
	bool is_isolated <- false;
	building my_home; building my_work; district my_district; 
	point target; float infection_time; float isolation_start_time;

	reflex commute {
		// When is_locked_down becomes false, this check passes and agents move again
		bool district_restricted <- (my_district != nil) and (my_district.is_locked_down);
		if (is_isolated or district_restricted) { 
			if (location distance_to my_home.location > 5#m and target = nil) {
				target <- any_location_in(my_home);
			}
			return; 
		}
		
		if (current_date.hour = 8 and target = nil) {
			district work_district <- district closest_to my_work;
			if (work_district != nil and !work_district.is_locked_down) {
				target <- any_location_in(my_work);
			}
		}
		if (current_date.hour = 18 and target = nil) { target <- any_location_in(my_home); }
	}

	reflex move when: target != nil {
		do goto target: target on: road_network;
		if (location = target) { target <- nil; } 
	}

	reflex spread_virus when: is_infected and !is_recovered {
		bool restricted <- (my_district != nil and my_district.is_locked_down) or is_isolated;
		if (location distance_to my_home.location < 10#m and restricted) { return; }
		ask people at_distance 5.0 {
			if (!self.is_infected and !self.is_recovered) {
				if flip(0.33) { self.is_infected <- true; self.infection_time <- time; }
			}
		}
	}
	
	reflex recover_or_die when: is_infected and !is_recovered {
		if (time - infection_time) >= 10 #days {
			if flip(death_rate) { nb_dead <- nb_dead + 1; do die; }
			else {
				is_infected <- false; is_recovered <- true; is_isolated <- false;
			}
		}
	}
	aspect circle { draw circle(12) color: is_infected ? #red : (is_recovered ? #yellow : #green); }
}

species road { aspect geom { draw shape color: #black; } }
species building { aspect geom { draw shape color: #gray; } }

experiment main type: gui {
	output {
		monitor "Active Infections" value: nb_infected;
		monitor "Total Dead" value: nb_dead;
		monitor "Locked Districts" value: nb_districts_locked;
		
		display map {
			species district aspect: base;
			species road aspect: geom;
			species building aspect: geom;
			species people aspect: circle;			
		}
		display chart_display {
			chart "SIRD District Lockdown Tracking" type: series {
				data "Susceptible" value: nb_infectible color: #green;
				data "Infected" value: nb_infected color: #red;
				data "Recovered" value: nb_recovered color: #yellow;
				data "Dead" value: nb_dead color: #black;
			}
		}
	}
}