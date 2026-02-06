model lockdown_disabled_with_vaccine_logic

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
	float daily_testing_rate <- 0.3; 
	// District lockdown duration is kept in parameters but never triggered
	int district_lockdown_duration <- 14 #days;
	
	// Hospital & Vaccine Parameters
	int hospital_capacity <- 300;
	int hospital_occupancy <- 0;
	bool vaccine_available <- false;
	bool virus_is_mutated <- false;
	bool is_incurable_strain <- false;
	float reinfection_chance <- 0.01; 
	
	// GIS DATA
	file roads_shapefile <- file("../includes/roads.shp");
	file buildings_shapefile <- file("../includes/buildings.shp");
	geometry shape <- envelope(roads_shapefile);	
	graph road_network;
	building hospital;
	
	// TRACKING
	int nb_infectible <- 0 update: people count (!each.is_infected and !each.is_recovered);
	int nb_infected <- 0 update: people count (each.is_infected);
	int nb_recovered <- 0 update: people count (each.is_recovered);
	int nb_dead <- 0; 
	
	init {
		create road from: roads_shapefile;
		road_network <- as_edge_graph(road);		
		create building from: buildings_shapefile;
		hospital <- one_of(building);
		
		create people number: nb_people {
			my_home <- one_of(building);
			my_work <- one_of(building);
			location <- any_location_in(my_home);
			my_district <- district closest_to self; 
		}
		ask nb_infected_init among people { is_infected <- true; infection_time <- 0.0; }
	}
	
	reflex daily_logic when: every(1 #day) {
		int day_num <- int(time / #day);
		if (day_num >= 5 and !vaccine_available) {
			vaccine_available <- true;
			write ">>> Day " + day_num + ": Vaccine rollout initiated.";
		}
		
		if (nb_infected > 100 and !virus_is_mutated and flip(0.01)) {
			virus_is_mutated <- true;
			if (flip(0.5)) {
				is_incurable_strain <- true; 
				write ">>> Day " + day_num + ": ALERT! Virus has mutated into an INCURABLE strain.";
			} else {
				proba_infection <- proba_infection * 1.01; 
				write ">>> Day " + day_num + ": ALERT! Virus has mutated to spread 1% faster.";
			}
		}

		write "--- DAY " + day_num + " REPORT ---";
		write "  Stats: [S:" + nb_infectible + " | I:" + nb_infected + " | R:" + nb_recovered + " | D:" + nb_dead + "]";
		write "  Hospital: " + hospital_occupancy + " / " + hospital_capacity;
	}

	reflex government_intervention when: every(1 #day) {
		list<people> tested_people <- (daily_testing_rate * nb_people) among people;
		int vaccines_given_today <- 0;

		ask tested_people {
			if (self.is_infected) {
				if (hospital_occupancy < hospital_capacity and !self.is_in_hospital) {
					self.is_in_hospital <- true;
					hospital_occupancy <- hospital_occupancy + 1;
					self.target <- any_location_in(hospital);
				} else if (!self.is_isolated) {
					self.is_isolated <- true;
					self.isolation_start_time <- time;
					self.target <- any_location_in(self.my_home);
				}
				// LOCKDOWN LOGIC REMOVED FROM HERE
			} 
			else if (vaccine_available and vaccines_given_today < 50 and !self.is_vaccinated) {
				self.is_vaccinated <- true;
				self.is_recovered <- true; 
				vaccines_given_today <- vaccines_given_today + 1;
			}
		}
	}
}

grid district width: 5 height: 4 {
	bool is_locked_down <- false;
	float lockdown_start_time;
	// Logic remains but since is_locked_down is never set to true, this won't fire
	reflex update_lockdown when: is_locked_down {
		if (time - lockdown_start_time) >= district_lockdown_duration { is_locked_down <- false; }
	}
	aspect base {
		draw shape color: is_locked_down ? rgb(255, 0, 0, 80) : rgb(255, 255, 255, 0) border: #black;
	}
}

species people skills:[moving] {		
	bool is_infected <- false;
	bool is_recovered <- false;
	bool is_isolated <- false;
	bool is_in_hospital <- false;
	bool is_vaccinated <- false;
	int days_since_infected <- 0;
	
	building my_home; building my_work; district my_district; 
	point target; float infection_time; float isolation_start_time;

	reflex update_timer when: is_infected and every(1 #day) {
		days_since_infected <- days_since_infected + 1;
	}

	reflex commute {
		// District restriction check removed; only isolation/hospitalization restricts movement
		bool restricted <- is_isolated or is_in_hospital;
		if (restricted) { 
			point safe_spot <- is_in_hospital ? hospital.location : my_home.location;
			if (location distance_to safe_spot > 5#m and target = nil) {
				target <- any_location_in(is_in_hospital ? hospital : my_home);
			}
			return; 
		}
		if (current_date.hour = 8 and target = nil) {
			target <- any_location_in(my_work); // No longer checks district lockdown
		}
		if (current_date.hour = 18 and target = nil) { target <- any_location_in(my_home); }
	}

	reflex move when: target != nil {
		do goto target: target on: road_network;
		if (location = target) { target <- nil; } 
	}

	reflex spread_virus when: is_infected and !is_recovered {
		// Lockdown proximity check removed
		bool restricted <- is_isolated or is_in_hospital;
		if (restricted and location distance_to my_home.location < 10#m) { return; }
		ask people at_distance infection_distance {
			if (!self.is_infected) {
				float current_proba <- self.is_vaccinated ? (proba_infection * reinfection_chance) : proba_infection;
				if (self.is_recovered and !self.is_vaccinated) { current_proba <- 0.0; } 
				
				if flip(current_proba) { 
					self.is_infected <- true; 
					self.is_recovered <- false;
					self.infection_time <- time; 
				}
			}
		}
	}
	
	reflex recover_or_die when: is_infected {
		if (time - infection_time) >= infectious_period {
			if (is_incurable_strain) { return; } 
			float current_death_risk <- death_rate * (1.05 ^ days_since_infected);
			float final_risk <- is_in_hospital ? current_death_risk / 2 : current_death_risk;
			if flip(final_risk) { 
				if (is_in_hospital) { hospital_occupancy <- hospital_occupancy - 1; }
				nb_dead <- nb_dead + 1; 
				do die; 
			} else {
				if (is_in_hospital) { hospital_occupancy <- hospital_occupancy - 1; }
				is_infected <- false; is_recovered <- true; is_isolated <- false; is_in_hospital <- false;
				days_since_infected <- 0;
			}
		}
	}

	aspect circle {
		rgb col <- #green;
		if (is_vaccinated) { col <- #cyan; }
		if (is_infected) { col <- #red; }
		if (is_recovered and !is_vaccinated) { col <- #yellow; }
		if (is_in_hospital) { col <- #blue; }
		draw circle(12) color: col; 
	}
}

species road { aspect geom { draw shape color: #black; } }
species building { aspect geom { draw shape color: (self = hospital) ? #blue : #gray; } }

experiment main type: gui {
	output {
		display map {
			species district aspect: base;
			species road aspect: geom;
			species building aspect: geom;
			species people aspect: circle;	
			overlay position: {5, 5} size: {180 #px, 180 #px} background: #white border: #black {
				draw "LEGEND" at: {10 #px, 20 #px} color: #black font: font("SansSerif", 14, #bold);
				draw circle(5 #px) at: {15 #px, 45 #px} color: #green;
				draw "Healthy" at: {30 #px, 50 #px} color: #black font: font("SansSerif", 12);
				draw circle(5 #px) at: {15 #px, 65 #px} color: #cyan;
				draw "Vaccinated" at: {30 #px, 70 #px} color: #black font: font("SansSerif", 12);
				draw circle(5 #px) at: {15 #px, 85 #px} color: #red;
				draw "Infected" at: {30 #px, 90 #px} color: #black font: font("SansSerif", 12);
				draw circle(5 #px) at: {15 #px, 105 #px} color: #yellow;
				draw "Recovered" at: {30 #px, 110 #px} color: #black font: font("SansSerif", 12);
				draw circle(5 #px) at: {15 #px, 125 #px} color: #blue;
				draw "In Hospital" at: {30 #px, 130 #px} color: #black font: font("SansSerif", 12);
			}		
		}
		display chart_display {
			chart "Epidemic Curve (No Lockdown)" type: series {
				data "Healthy" value: nb_infectible color: #green;
				data "Infected" value: nb_infected color: #red;
				data "Recovered" value: nb_recovered color: #yellow;
				data "Dead" value: nb_dead color: #black;
			}
		}
	}
}