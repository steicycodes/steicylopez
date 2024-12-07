//--------------------------------------------------------------------------- Prepping Additional Waves
clear all

//Define dataset paths in one line or correctly with continuation
	local datasets /Users/steicyl/Desktop/Thesis/DataFiles/OGs/uas461.dta /Users/steicyl/Desktop/Thesis/DataFiles/OGs/uas475.dta /Users/steicyl/Desktop/Thesis/DataFiles/OGs/uas502.dta /Users/steicyl/Desktop/Thesis/DataFiles/OGs/uas559.dta /Users/steicyl/Desktop/Thesis/DataFiles/OGs/uas584.dta

    foreach file in `datasets'{
		use uasid gender age maritalstatus education hisplatino white black asian hhincome working hhmemberage* sl057a sl058a sl056 using "`file'", clear
		
      //Extract the last 7 characters of the file name (ex: uas461.dta)
    local filename = substr("`file'", strlen("`file'") - 9, 10)
    
    //Extract wave number (ex: 461)
    local wave = substr("`filename'", 4, 3)
	
	//saving the source as a variable to keep as a marker of wave source
	gen survey_source = "`wave'"
	destring survey_source, replace
	
	save "/Users/steicyl/Desktop/Thesis/DataFiles/clean_`filename'", replace
}

//--------------------------------------------------------------------------- Prepping Remote Exposure
//-------------------------------------------------------- Load data in
	clear all
	
	use uasid survey_source e_remote using "/Users/steicyl/Desktop/Thesis/DataFiles/OGs/covidpanel_us_stata_feb_3_2021_mergedschoolsupply_political_STATA13.dta"

	save "/Users/steicyl/Desktop/Thesis/DataFiles/Clean Schooltype", replace
	
//--------------------------------------------------------------------------- Prepping Political
//-------------------------------------------------------- Load data in
	clear all
	use "/Users/steicyl/Desktop/Thesis/DataFiles/OGs/Longitudinal.dta"

//pulling only needed variables
	keep uasid polldate today_vote pr_urban3 pr_statereside

//sorting and labeling observations
	sort uasid polldate
	by uasid: gen nobs=_n
	by uasid: gen tobs=_N
	
//Keep just the latest observed poll information
	keep if nobs==tobs
	replace today_vote = 8 if today_vote > 2 & today_vote != . & today_vote != 5 
		//grouping other candidates together
	tabulate today_vote, gen(m)
		rename m1 bidenvoter
		rename m2 trumpvoter
		rename m3 undecidedvoter
		rename m4 othervoter

//renaming for clarity and to match later code
	rename pr_urban3 urbanicity
	rename pr_statereside state
	
	drop today_vote polldate
	
//saving
	save "/Users/steicyl/Desktop/Thesis/DataFiles/Clean Longitudinal Political.dta", replace

	clear all
//--------------------------------------------------------------------------- Analysis
//-------------------------------------------------------- Load data in
	use uasid start_date survey_source gender age maritalstatus education hisplatino white black asian hhincome hhmemberage* working sl030 sl079 sl057a sl058a sl056 trust_source* cr054 prisk_infection prisk_die sl058 sl030a sl052 ch001b using "/Users/steicyl/Desktop/Thesis/DataFiles/OGs/covidpanel_us_stata_jul_10_2023.dta"

//merging post covid waves
	append using "/Users/steicyl/Desktop/Thesis/DataFiles/clean_uas461.dta"
	append using "/Users/steicyl/Desktop/Thesis/DataFiles/clean_uas475.dta"
	append using "/Users/steicyl/Desktop/Thesis/DataFiles/clean_uas502.dta"
	append using "/Users/steicyl/Desktop/Thesis/DataFiles/clean_uas559.dta"
	append using "//Users/steicyl/Desktop/Thesis/DataFiles/clean_uas584.dta"

//merging with political
	merge m:1 uasid using "/Users/steicyl/Desktop/Thesis/DataFiles/Clean Longitudinal Political.dta"
		drop if _merge == 2 //removing unmatched IDs from political
		drop _merge //drop the merge indicator
	
//merging with school type availability
	merge 1:1 uasid survey_source using "/Users/steicyl/Desktop/Thesis/DataFiles/Clean Schooltype.dta"
		drop if _merge == 2 //removing unmatched IDs from political
		drop _merge //drop the merge indicator
//-------------------------------------------------------- Pulling time invariant variables
//race and ethnicity
		gen race_eth=1 if white==1 & hisplatino==0
		replace race_eth=2 if black==1 & hisplatino==0
		replace race_eth=3 if asian==1 & hisplatino==0
		replace race_eth=4 if hisplatino==1
		replace race_eth=5 if white==0 & black==0 & hisplatino==0 & asian==0
		
		//Note with these dummies we are assigning value zero if they have missing
		
//marriage
	gen married_partner= maritalstatus==1  //if respondent is married and their partner lives with them = 1
	replace married_partner=1 if maritalstatus==2 // if respondent is not married but living with partner = 1
 
//education
		gen education2= 1 if (education<=9 & !missing(education)) 
			//high school degree or lower
		replace education2 = 2 if ((education<=12 & education>9)& !missing(education))
			//some college +Associates degree
		replace education2 = 3 if ((education>12) & !missing(education))
			//4 year college graduate

// parent age
	gen ageres = .
		replace ageres = 1 if age<=29 & !missing(age)
		replace ageres = 2 if (age<=39 & age>29) & !missing(age)
		replace ageres = 3 if (age<=49 & age>39) & !missing(age)
		replace ageres = 4 if (age<=59 & age>49) & !missing(age)
		replace ageres = 5 if (age>=60) & !missing(age)
	
//medical condition
	gen medcond = .
		replace medcond = 0 if (cr054=="11") 
			//none of the above
		replace medcond = 1 if (missing(medcond) & !(missing(cr054)|cr054==".z var not in wv (or always skipped)"|cr054==".e"|cr054== ".a"))
			//immunocompromising condition as diagnosed by a doctor
				
//organize trust variables
	//media trust variables 
		foreach var in trust_source_cbs trust_source_cnn trust_source_abc trust_source_locn trust_source_loctv trust_source_msnbc trust_source_natn trust_source_nbc trust_source_pubtv {
			rename `var' m_`var'
		}
	
	//institutional trust variables
		foreach var in trust_source_cdc trust_source_hhs trust_source_ph trust_source_pubh trust_source_who {
			rename `var' i_`var'
		}

//factors
	factor m_trust_source_abc m_trust_source_cbs m_trust_source_cnn m_trust_source_locn m_trust_source_loctv m_trust_source_msnbc m_trust_source_natn m_trust_source_nbc m_trust_source_pubtv, pcf
	rotate
	predict mediatrust1
	
	factor i_trust_source_cdc i_trust_source_hhs i_trust_source_ph i_trust_source_pubh i_trust_source_who, pcf
	rotate
	predict institutionaltrust1
		
	
//loop to max all variables
	foreach var in race_eth gender married_partner education2 ageres medcond trumpvoter urbanicity i_trust_source_cdc i_trust_source_hhs i_trust_source_ph i_trust_source_pubh i_trust_source_who m_trust_source_abc m_trust_source_cbs m_trust_source_cnn m_trust_source_locn m_trust_source_loctv m_trust_source_msnbc m_trust_source_natn m_trust_source_nbc m_trust_source_pubtv trust_source_fox mediatrust1 institutionaltrust1{
		bysort uasid: egen c_`var' = max(`var')
	}	
	
//-------------------------------------------------------- Labeling time invariant

	label variable race_eth "Racial/Ethnic Background"
	label define race_eth 1 "White" 2 "Black" 3 "Asian" 4 "Hispanic" 5 "Other"
	label values race_eth race_eth
	
	label variable c_married_partner "Marital Status"
	label define c_married_partner 1 "Married" 2 "Not Married/Married But Not Living Together"
	label values c_married_partner c_married_partner
	
	label variable c_education "Education"
	label define c_education 1 "No College" 2 "Some College" 3 "College Graduate"
	label values c_education c_education
	
	label variable c_ageres "Age of Respondent"
	label define c_ageres 1 "Under 30" 2 "30 to 39" 3 "40 to 49" 4 "50 to 59" 5 "60 and over"
	label values c_ageres c_ageres
	
	label variable c_medcond "Medical Condition"
	label define c_medcond 0 "No Immunocompromising Conditions" 1 "Diagnosed Immunocompromising Medical Condition" 
	label values c_medcond c_medcond

	label variable c_trumpvoter "Trump Supporter"
	label define c_trumpvoter 0 "Not a Trump Supporter" 1 "Either Voted or Reported Trust in Trump"
	label values c_trumpvoter c_trumpvoter

	label variable c_urbanicity "Urbanicity"
	label define c_urbanicity 0 "Rural" 1 "Mixed" 2 "Urban"
	label values c_urbanicity c_urbanicity 
	
//-------------------------------------------------------- Pulling time variant

//school type 
	//variables reporting schooltype of child was not consistent throughout the survey waves 
	//summarization of reported school type is done through one variable
	
	//school type dummies
	gen public = 0
		replace public = 1 if (sl030 == 1|sl058a == 1|sl030 == 2|sl030 == 3|sl058a == 3|sl079 == 1|sl079 == 2|sl079 == 3)	
	gen private = 0
		replace private = 1 if (sl030 == 4|sl058a == 2|sl079 == 4)
	gen home = 0
		replace home = 1 if (sl030 == 5|sl057a == 2|sl079 == 5)
	gen other_sch = 0 
		replace other_sch = 1 if (sl057a == 3|sl030 == 6|sl058a == 5|sl079 == 6|sl058a == 4)
		
	//school type variable
		gen schooltype=0
			replace schooltype = 1 if (public == 1 & (private==0|home == 0))
			replace schooltype = 2 if (private == 1)
			replace schooltype = 3 if (home == 1 & private == 0)
			replace schooltype = 4 if (other_sch ==1 & (public==0|home==0|private ==0))
	//droping those that dont have kids or just didnt answer schooltype question
		drop if (public==0 & private==0 & home==0 & other_sch ==0)
	
	//labeling 
		label variable schooltype "School Attendance Mode"
		label define schooltype 1 "Public/Charter/Magnet" 2 "Private" 3 "Homeschooled" 4 "Not Enrolled/Other/Virtual"
		label values schooltype schooltype
		
//age of the kids
	gen agekid = .
		replace agekid = 1 if (sl056<6) & !missing(sl056)
		replace agekid = 2 if (sl056>5 & sl056<10) & !missing(sl056)
		replace agekid = 3 if (sl056>9) & !missing(sl056)

	//labeling 
		label variable agekid "Age Group of Child"
		label define agekid 1 "Preschool to Elementary" 2 "Middle School to Junior High" 3 "High School"
		label values agekid agekid
		
//income
	gen income = .
		replace income = 1 if hhincome<= 11 & !missing(hhincome)
		replace income = 2 if (hhincome == 12|hhincome == 13|hhincome == 14) & !missing(hhincome)
		replace income = 3 if hhincome>14 & !missing(hhincome)
		
	//labeling
		label variable income "Household Income"
		label define income 1 "Low Income" 2 " Middle Income" 3 "High Income"
		label values income income

//number of kids in household
	forvalues i = 1/27 {
		replace hhmemberage_`i' = 1 if hhmemberage_`i' < 18
		replace hhmemberage_`i' = 0 if hhmemberage_`i' >= 18
	}

	egen kids = rowtotal(hhmemberage*)
	
	//Since those that didnt answer schooltype or age of child questions they have atleast one child
		replace kids = 1 if kids == 0 //answered schooltype questions
	
	//labeling
		label variable kids "Number of Kids in the Household"

//-------------------------------------------------------- Percieved Risk of COVID(Seperate from other factors because was not maxed)
//risk of covid

	factor prisk_infection prisk_die, pcf
	rotate
	predict percievedrisk
	
//-------------------------------------------------------- Removing other vars

	keep uasid survey_source working e_remote c_gender c_race_eth c_married_partner c_education2 c_ageres c_medcond c_trumpvoter c_urbanicity agekid income kids c_mediatrust1 c_institutionaltrust1 percievedrisk schooltype c_trust_source_fox publicexit
	
//-------------------------------------------------------- Switching Dummies
sort uasid survey_source

//Switchers
	gen switch = 0
	bysort uasid: replace switch = 1 if _n > 1 & (schooltype != schooltype[_n-1])
	
	//labeling
		label variable switch "Switching School Type"
	
//Public School Exit
	gen publicexit = 0
	bysort uasid: replace publicexit = 1 if ((_n > 1) & (schooltype != schooltype[_n-1]) & (schooltype[_n-1] == 1))
	
	//labeling
		label variable switch "Exiting Public School"

//Public school exit for homeschooling
	gen publicexithome = 0
	replace publicexithome = 1 if (publicexit == 1 & (schooltype==3))
	
	//labeling
		label variable switch "Exiting Public School for Homeschooling"
		
//Public school exit for private
	gen publicexitprivate = 0
	replace publicexitprivate = 1 if (publicexit == 1 & (schooltype==2))
	
		//labeling
		label variable switch "Exiting Public School for Private School"
		
	
	save "/Users/steicyl/Desktop/Thesis/Stata and R/D5_Thesis", replace

//-------------------------------------------------------- Dummies for missing variables

		foreach var in c_trumpvoter c_urbanicity percievedrisk c_mediatrust1 e_remote{
		gen miss_`var' = missing(`var') //this variable will be 1 if the OG variable was missing, 0 if not missing
		replace `var' = 0 if missing(`var') //replacing missing values with 0 to create interaction later in the regression
	} 
	
//-------------------------------------------------------- Removing unecessary variables
	save "/Users/steicyl/Desktop/Thesis/Stata and R/D6_Thesis", replace
	
//-------------------------------------------------------- Regressions focused on public
//--------------------------------------Public School Survival Model
	preserve
//keeping public school starters
	sort uasid survey_source
	bysort uasid: gen publicstarter = 1 if sum(_n == 1 & schooltype==1)==1 //uses first observation to mark public school starters
	keep if publicstarter == 1 //keeping only public school starters
	
	gen flag = publicexit
	bysort uasid : replace flag = flag[_n-1] if flag[_n-1] == 1 
		//replaces the obs to one if the obs before that was one, done so after family leaves public there are ones

	gen survival = flag
		bysort uasid: replace survival = . if flag[_n-1] == 1
		
	drop publicstarter flag 
	
//regression of public school starters survival 
	logit survival i.survey_source i.c_rethnic c_maritalstatus c_medcond c_trumpsupport i.c_urbanicity e_remote c_gender i.c_education c_ageres i.agekid working i.income nmiss_c_trumpsupport nmiss_c_urbanicity nmiss_percievedrisk nmiss_institutionaltrust nmiss_mediatrust nmiss_e_remote institutionaltrust mediatrust percievedrisk c_trust_source_fox kids, robust
	
	margins, dydx(*)
	cd "/Users/steicyl/Desktop/Thesis/DataFiles/Results"
	outreg2 using "survivalpublic.xls", replace
	restore
//--------------------------------------Public School with Specificity Survival Model
	preserve
	
//keeping public school starters
	sort uasid survey_source
	bysort uasid: gen publicstarter = 1 if sum(_n == 1 & schooltype==1)==1 
		//uses first observation to mark public school starters
	keep if publicstarter == 1 //keeping only public school starters
	
	gen flag = publicexit
	bysort uasid : replace flag = flag[_n-1] if flag[_n-1] == 1 
		//replaces the obs to one if the obs before that was one, done so after family leaves public there are ones

	gen survival = flag
		bysort uasid: replace survival = . if flag[_n-1] == 1
		//makes observations after switch missing 
	
//modifying survival variable 
	//recoding so that switch to private = 2, homeschooling = 3, and other = 4
		replace survival = 1 if survival==1 & schooltype == 2
		replace survival = 2 if survival==1 & schooltype == 3
		replace survival = 3 if survival==1 & schooltype == 4
		
	//labeling 
	label define survival 0 "Public" 1 "Private" 2 "Homeschooled" 3 "Other"
	label values survival survival
	
//running the regression
	mlogit survival i.survey_source working c_gender i.c_race_eth c_married_partner i.c_education2 c_ageres c_medcond c_trumpvoter i.c_urbanicity i.agekid i.income kids percievedrisk c_mediatrust1 c_institutionaltrust1 c_trust_source_fox, robust
	
	margins, dydx(*) //pulling unit changes

	outreg2 using "survivalpublic.xls", append
	restore 
//--------------------------------------Public School with Specificity Survival Model with Split Phases
clear all
//---------------------------------------------------Loading the data in 
use "/Users/steicyl/Desktop/Thesis/Stata and R/D6_Thesis.dta"
cd "/Users/steicyl/Desktop/Thesis/DataFiles/Results"
//individual survival models 
//analysis by phases 
//phase 1 is august 2020 to dec 2020
//phase 2 is jan 2020 to june 2020
//phase 3 aug 2021 to june 2022
//phase 4 aug 2022 to june 2023

//Phase 1
preserve
//keeping public school starters
	sort uasid survey_source
	bysort uasid: gen publicstarter = 1 if sum(_n == 1 & schooltype==1)==1 //uses first observation to mark public school starters
	keep if publicstarter == 1 //keeping only public school starters
	
	gen flag = publicexit
	bysort uasid : replace flag = flag[_n-1] if flag[_n-1] == 1 
		//replaces the obs to one if the obs before that was one, done so after family leaves public there are ones

	gen survival = flag
		bysort uasid: replace survival = . if flag[_n-1] == 1
		//makes observations after switch missing 
	
//modifying survival variable 
	//recoding so that switch to private = 2, homeschooling = 3, and other = 4
		replace survival = 1 if survival==1 & schooltype == 2
		replace survival = 2 if survival==1 & schooltype == 3
		replace survival = 3 if survival==1 & schooltype == 4
		
	//labeling 
	label define survival 0 "Public" 1 "Private" 2 "Homeschooled" 3 "Other"
	label values survival survival
	
//keeping only relevant waves 
 	keep if survey_source>=264 & survey_source<=274 // sept to dec 2020

//running the regression
	mlogit survival i.survey_source working c_gender i.c_race_eth c_married_partner i.c_education2 c_ageres c_medcond c_trumpvoter i.c_urbanicity i.agekid i.income kids percievedrisk c_mediatrust1 c_institutionaltrust1 c_trust_source_fox miss_c_trumpvoter miss_c_urbanicity miss_percievedrisk miss_c_mediatrust1 e_remote miss_e_remote, robust
	
	margins, dydx(*) //pulling unit changes

	outreg2 using "survivalpublic2.xls", replace
	restore 
	
//Phase 2
	preserve

//keeping public school starters
	sort uasid survey_source
	bysort uasid: gen publicstarter = 1 if sum(_n == 1 & schooltype==1)==1 //uses first observation to mark public school starters
	keep if publicstarter == 1 //keeping only public school starters
	
	gen flag = publicexit
	bysort uasid : replace flag = flag[_n-1] if flag[_n-1] == 1 
		//replaces the obs to one if the obs before that was one, done so after family leaves public there are ones

	gen survival = flag
		bysort uasid: replace survival = . if flag[_n-1] == 1
		//makes observations after switch missing 
	
//modifying survival variable 
	//recoding so that switch to private = 2, homeschooling = 3, and other = 4
		replace survival = 1 if survival==1 & schooltype == 2
		replace survival = 2 if survival==1 & schooltype == 3
		replace survival = 3 if survival==1 & schooltype == 4
		
	//labeling 
	label define survival 0 "Public" 1 "Private" 2 "Homeschooled" 3 "Other"
	label values survival survival
	
 //keeping only relevant waves 
	keep if survey_source>=276 & survey_source<=346 // jan to june 2021
 
//running the regression
	mlogit survival i.survey_source working c_gender i.c_race_eth c_married_partner i.c_education2 c_ageres c_medcond c_trumpvoter i.c_urbanicity i.agekid i.income kids percievedrisk c_mediatrust1 c_institutionaltrust1 c_trust_source_fox miss_c_trumpvoter miss_c_urbanicity miss_percievedrisk miss_c_mediatrust1, robust
	
	margins, dydx(*) //pulling unit changes

	outreg2 using "survivalpublic2.xls", append
	restore
	
//Phase 3 
	preserve

//keeping public school starters
	sort uasid survey_source
	bysort uasid: gen publicstarter = 1 if sum(_n == 1 & schooltype==1)==1 //uses first observation to mark public school starters
	keep if publicstarter == 1 //keeping only public school starters
	
	gen flag = publicexit
	bysort uasid : replace flag = flag[_n-1] if flag[_n-1] == 1 
		//replaces the obs to one if the obs before that was one, done so after family leaves public there are ones

	gen survival = flag
		bysort uasid: replace survival = . if flag[_n-1] == 1
		//makes observations after switch missing 
	
//modifying survival variable 
	//recoding so that switch to private = 2, homeschooling = 3, and other = 4
		replace survival = 1 if survival==1 & schooltype == 2
		replace survival = 2 if survival==1 & schooltype == 3
		replace survival = 3 if survival==1 & schooltype == 4
		
	//labeling 
	label define survival 0 "Public" 1 "Private" 2 "Homeschooled" 3 "Other"
	label values survival survival
	
//keeping only relevant waves 
	keep if survey_source>=350 & survey_source<=461 // aug 2021 to june 2022
 	
//running the regression
	mlogit survival i.survey_source working c_gender i.c_race_eth c_married_partner i.c_education2 c_ageres c_medcond c_trumpvoter i.c_urbanicity i.agekid i.income kids percievedrisk c_mediatrust1 c_institutionaltrust1 c_trust_source_fox miss_c_trumpvoter miss_c_urbanicity miss_percievedrisk miss_c_mediatrust1, robust
	
	margins, dydx(*) //pulling unit changes

	outreg2 using "survivalpublic2.xls", append
	restore 
	
//Phase 4
	preserve

//keeping public school starters
	sort uasid survey_source
	bysort uasid: gen publicstarter = 1 if sum(_n == 1 & schooltype==1)==1 //uses first observation to mark public school starters
	keep if publicstarter == 1 //keeping only public school starters
	
	gen flag = publicexit
	bysort uasid : replace flag = flag[_n-1] if flag[_n-1] == 1 
		//replaces the obs to one if the obs before that was one, done so after family leaves public there are ones

	gen survival = flag
		bysort uasid: replace survival = . if flag[_n-1] == 1
		//makes observations after switch missing 
	
//modifying survival variable 
	//recoding so that switch to private = 2, homeschooling = 3, and other = 4
		replace survival = 1 if survival==1 & schooltype == 2
		replace survival = 2 if survival==1 & schooltype == 3
		replace survival = 3 if survival==1 & schooltype == 4
		
	//labeling 
	label define survival 0 "Public" 1 "Private" 2 "Homeschooled" 3 "Other"
	label values survival survival
 	
//keep only relevant waves 
	keep if survey_source>=475 & survey_source<=559 // july 2022 to july 2023

//running the regression
	mlogit survival i.survey_source working c_gender i.c_race_eth c_married_partner i.c_education2 c_ageres c_medcond c_trumpvoter i.c_urbanicity i.agekid i.income kids percievedrisk c_mediatrust1 c_institutionaltrust1 c_trust_source_fox miss_c_trumpvoter miss_c_urbanicity miss_percievedrisk miss_c_mediatrust1, robust
	
	margins, dydx(*) //pulling unit changes

	outreg2 using "survivalpublic2.xls", append

restore

//---------------------------------------------------- Anytime Away From Public School
clear all
//------------------------------------------------Load data
use "/Users/steicyl/Desktop/Thesis/Stata and R/D5_Thesis.dta"

//keeping public school starters
	sort uasid survey_source
	bysort uasid: gen publicstarter = 1 if sum(_n == 1 & schooltype==1)==1 //uses first observation to mark public school starters
	keep if publicstarter == 1 //keeping only public school starters

//creating variable to identify any time away from public school 
	gen awaypublic = !(schooltype==1)
	
//running regression (General time away from public)
	logit awaypublic i.survey_source working c_gender i.c_race_eth c_married_partner i.c_education2 c_ageres c_medcond c_trumpvoter i.c_urbanicity i.agekid i.income kids percievedrisk c_mediatrust1 c_institutionaltrust1 c_trust_source_fox, robust
	
	margins,dydx(*)
	
	cd "/Users/steicyl/Desktop/Thesis/DataFiles/Results"
	outreg2 using "awaypublic.xls", replace
	
//running regression (Specific to schooltype)
replace awaypublic = 2 if schooltype==3 & awaypublic==1 //homeschooling
replace awaypublic = 3 if schooltype==4 & awaypublic==1 //otherschool

	mlogit awaypublic i.survey_source working c_gender i.c_race_eth c_married_partner i.c_education2 c_ageres c_medcond c_trumpvoter i.c_urbanicity i.agekid i.income kids percievedrisk c_mediatrust1 c_institutionaltrust1 c_trust_source_fox, robust
	
	margins,dydx(*)
	
	cd "/Users/steicyl/Desktop/Thesis/DataFiles/Results"
	outreg2 using "awaypublic.xls", append 
	
//----------------------------------------------------General Multinomial Model
clear all
//----------------------------------------------Load data
	use "/Users/steicyl/Desktop/Thesis/Stata and R/D6_Thesis.dta"
//All school modes

	mlogit schooltype i.survey_source working c_gender i.c_race_eth c_married_partner i.c_education2 c_ageres c_medcond i.c_urbanicity miss_c_urbanicity i.agekid i.income kids percievedrisk c_mediatrust1 c_institutionaltrust1 c_trust_source_fox miss_percievedrisk miss_c_mediatrust1 c_trumpvoter miss_c_trumpvoter, robust
		
	margins, dydx(*) //find marginal effects 
	
	cd "/Users/steicyl/Desktop/Thesis/DataFiles/Results" //set directory
	
	outreg2 using "multinomalschooltype1.xls", append //save as an excel
