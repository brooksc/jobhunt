// Metro-area data for location filtering.

export const METRO_DATA = {
  wa: { label: 'Washington', metros: {
    seattle: { label: 'Seattle Metro', cities: ['Seattle','Bellevue','Redmond','Kirkland','Bothell','Renton','Issaquah','Sammamish','Kent','Federal Way','Shoreline','Kenmore','Woodinville','Mercer Island'] },
    spokane: { label: 'Spokane', cities: ['Spokane','Spokane Valley','Liberty Lake'] },
  }},
  ca: { label: 'California', metros: {
    'bay-area': { label: 'SF Bay Area', cities: ['San Francisco','San Jose','Oakland','Sunnyvale','Santa Clara','Palo Alto','Mountain View','Menlo Park','Cupertino','Fremont','Berkeley','Redwood City','Foster City','San Mateo','Burlingame','South San Francisco','Emeryville','Walnut Creek','San Ramon','Pleasanton','Concord','Dublin'] },
    la: { label: 'Los Angeles Metro', cities: ['Los Angeles','Santa Monica','Culver City','El Segundo','Playa Vista','Long Beach','Burbank','Glendale','Pasadena','Irvine','Manhattan Beach','Hermosa Beach','Redondo Beach','Torrance','El Segundo','West Hollywood','Beverly Hills','Marina del Rey'] },
    'san-diego': { label: 'San Diego', cities: ['San Diego','La Jolla','Carlsbad','Solana Beach','Del Mar','Chula Vista','El Cajon'] },
    sacramento: { label: 'Sacramento', cities: ['Sacramento','Roseville','Folsom','Elk Grove','Davis','Rancho Cordova'] },
  }},
  tx: { label: 'Texas', metros: {
    austin: { label: 'Austin', cities: ['Austin','Round Rock','Cedar Park','Georgetown','Pflugerville','Kyle','Buda','Leander','San Marcos'] },
    'dallas-fort-worth': { label: 'Dallas–Fort Worth', cities: ['Dallas','Fort Worth','Plano','Irving','Frisco','Allen','McKinney','Richardson','Garland','Addison','Carrollton','Grapevine','Southlake','Arlington','Flower Mound'] },
    houston: { label: 'Houston', cities: ['Houston','Sugar Land','The Woodlands','Pearland','Katy','Stafford','Clear Lake'] },
    'san-antonio': { label: 'San Antonio', cities: ['San Antonio','New Braunfels','Boerne','Schertz'] },
  }},
  ny: { label: 'New York', metros: {
    nyc: { label: 'NYC Metro', cities: ['New York','Manhattan','Brooklyn','Queens','Bronx','Staten Island','Jersey City','Newark','Hoboken','White Plains','Yonkers','Stamford'] },
    albany: { label: 'Albany', cities: ['Albany','Troy','Schenectady'] },
  }},
  ma: { label: 'Massachusetts', metros: {
    boston: { label: 'Boston Metro', cities: ['Boston','Cambridge','Somerville','Waltham','Lexington','Burlington','Woburn','Malden','Quincy','Needham','Weston','Framingham','Natick'] },
  }},
  il: { label: 'Illinois', metros: {
    chicago: { label: 'Chicago Metro', cities: ['Chicago','Evanston','Naperville','Schaumburg','Oak Park','Lisle','Downers Grove','Rosemont','Skokie','Hoffman Estates'] },
  }},
  or: { label: 'Oregon', metros: {
    portland: { label: 'Portland Metro', cities: ['Portland','Beaverton','Hillsboro','Lake Oswego','Tigard','Vancouver','Gresham','Tualatin'] },
  }},
  co: { label: 'Colorado', metros: {
    denver: { label: 'Denver Metro', cities: ['Denver','Boulder','Aurora','Lakewood','Arvada','Westminster','Broomfield','Englewood','Centennial','Greenwood Village','Littleton'] },
  }},
  ga: { label: 'Georgia', metros: {
    atlanta: { label: 'Atlanta Metro', cities: ['Atlanta','Alpharetta','Marietta','Sandy Springs','Smyrna','Roswell','Johns Creek','Norcross','Peachtree City','Duluth'] },
  }},
  va: { label: 'Virginia', metros: {
    'northern-va': { label: 'Northern Virginia', cities: ['Arlington','Alexandria','Reston','Herndon','McLean','Tysons','Fairfax','Sterling','Chantilly','Ashburn','Vienna'] },
    richmond: { label: 'Richmond', cities: ['Richmond','Henrico','Chesterfield'] },
  }},
  nc: { label: 'North Carolina', metros: {
    'research-triangle': { label: 'Research Triangle', cities: ['Raleigh','Durham','Chapel Hill','Cary','Morrisville','Apex','Holly Springs'] },
    charlotte: { label: 'Charlotte', cities: ['Charlotte','Concord','Gastonia','Matthews','Huntersville'] },
  }},
  fl: { label: 'Florida', metros: {
    miami: { label: 'Miami Metro', cities: ['Miami','Fort Lauderdale','Boca Raton','West Palm Beach','Coral Gables','Doral','Aventura'] },
    orlando: { label: 'Orlando', cities: ['Orlando','Lake Mary','Maitland','Winter Park','Oviedo'] },
    tampa: { label: 'Tampa Bay', cities: ['Tampa','St. Petersburg','Clearwater','Sarasota'] },
    jacksonville: { label: 'Jacksonville', cities: ['Jacksonville'] },
  }},
  az: { label: 'Arizona', metros: {
    phoenix: { label: 'Phoenix Metro', cities: ['Phoenix','Scottsdale','Tempe','Mesa','Chandler','Gilbert','Glendale','Peoria','Surprise'] },
    tucson: { label: 'Tucson', cities: ['Tucson'] },
  }},
  ut: { label: 'Utah', metros: {
    'salt-lake-city': { label: 'Salt Lake City / Utah Valley', cities: ['Salt Lake City','Provo','Orem','Lehi','American Fork','Draper','Sandy','South Jordan','Murray','Lindon','Pleasant Grove'] },
  }},
  oh: { label: 'Ohio', metros: {
    columbus: { label: 'Columbus', cities: ['Columbus','Dublin','Westerville','New Albany','Grove City'] },
    cleveland: { label: 'Cleveland', cities: ['Cleveland','Beachwood','Independence','Solon','Strongsville'] },
    cincinnati: { label: 'Cincinnati', cities: ['Cincinnati','Blue Ash','Mason','Covington'] },
  }},
  pa: { label: 'Pennsylvania', metros: {
    philadelphia: { label: 'Philadelphia Metro', cities: ['Philadelphia','King of Prussia','Wayne','Malvern','Radnor','Horsham','Blue Bell','Conshohocken'] },
    pittsburgh: { label: 'Pittsburgh', cities: ['Pittsburgh','Cranberry Township','Canonsburg'] },
  }},
  nj: { label: 'New Jersey', metros: {
    'northern-nj': { label: 'Northern NJ', cities: ['Hoboken','Jersey City','Newark','Parsippany','Florham Park','Basking Ridge','Bridgewater','Princeton'] },
  }},
  md: { label: 'Maryland', metros: {
    'dc-metro': { label: 'DC / Baltimore Metro', cities: ['Baltimore','Columbia','Bethesda','Rockville','Silver Spring','Gaithersburg','Annapolis','Chevy Chase','Greenbelt'] },
  }},
  mi: { label: 'Michigan', metros: {
    detroit: { label: 'Detroit Metro', cities: ['Detroit','Ann Arbor','Dearborn','Troy','Southfield','Royal Oak','Auburn Hills','Livonia','Grand Rapids'] },
  }},
  mn: { label: 'Minnesota', metros: {
    minneapolis: { label: 'Minneapolis–St. Paul', cities: ['Minneapolis','St. Paul','Bloomington','Eden Prairie','Edina','Plymouth','Minnetonka','Maple Grove','Richfield'] },
  }},
};

// State name maps (abbrev → full and full → abbrev) for state-level matching
const STATE_ABBREV_TO_FULL = { wa:'Washington', ca:'California', tx:'Texas', ny:'New York', ma:'Massachusetts', il:'Illinois', or:'Oregon', co:'Colorado', ga:'Georgia', va:'Virginia', nc:'North Carolina', fl:'Florida', az:'Arizona', ut:'Utah', oh:'Ohio', pa:'Pennsylvania', nj:'New Jersey', md:'Maryland', mi:'Michigan', mn:'Minnesota' };

export function parsePreferredMetros(str) {
  if (!str) return [];
  return str.split(',').map(t => t.trim()).filter(Boolean).map(t => {
    const [state, metro] = t.split(':');
    return { state: state?.toLowerCase(), metro: metro?.toLowerCase() };
  }).filter(({ state, metro }) => state && metro);
}

export function expandMetros(str) {
  if (!str) return [];
  const seen = new Set();
  const result = [];
  const add = (v) => { const k = v.toLowerCase(); if (!seen.has(k)) { seen.add(k); result.push(v); } };

  const parsed = parsePreferredMetros(str);
  const addedStates = new Set();

  for (const { state, metro } of parsed) {
    const stateData = METRO_DATA[state];
    if (!stateData) continue;
    const metroData = stateData.metros[metro];
    if (!metroData) continue;

    // Add all cities in this metro
    for (const city of metroData.cities) add(city);

    // Add state abbreviation + full name once per state
    if (!addedStates.has(state)) {
      addedStates.add(state);
      add(state.toUpperCase()); // e.g. "WA"
      if (STATE_ABBREV_TO_FULL[state]) add(STATE_ABBREV_TO_FULL[state]); // e.g. "Washington"
    }
  }

  return result;
}
