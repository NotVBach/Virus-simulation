# VIRUS SIMULATION WITH GAMA

## Members:

- Dao Xuan Quy - 2440053
- Luong Thi Ngoc Diep - 2440056
- Nguyen Vu Bach - 2440050

## Introduction 

* This is the project of Group 8, **Subject Modeling and simulation of complex systems**, focusing on simluate Virus spreading behaviors in difference scenarios.
* Since I'm suck at handling large files, all the assets will be tranfered to Google Drive via: [Includes](https://drive.google.com/file/d/19FQTeO65CSfLlaO_saC4m3R5KiC59WQn/view?usp=sharing)

## TODO 
* Simulate difference scenarios with death rates from 1% to 100%
* Simulate difference scenarios with mutation rates increase from 1% to 100%, with the vacinated rates of 1% of population (the 1% population that are tested and keep lockdown by the gov)


### Binh Binh commit
- Base scenario
- Lockdown scenario
- Parameters

| Parameters | current Value | Interval (Min - Max) |
| :--- | :--- | :--- |
| `nb_people` | 3000 | |
| `nb_infected_init` | 10 | |
| `proba_infection` | 0.33 | |
| `infection_distance` | 5.0 | |
| `infectious_period` | 10 | |
| `death_rate` | 0.1 | 0.1 - 0.5 |
| `daily_testing_rate` | 0.1 | 0.01 - 0.5|
| `hospital_capacity` | 300 | 50 - 500|
| `vaccine_rollout_day` | 5 | 3 - 10 |
| `vaccine_daily_limit` | 50 | 10 - 100|
| `reinfection_chance` | 0.01 | |
| `mutation_chance` | 0.01 | 0.01 - 0.3|
| `district_lockdown_duration` | 14 | |
