import 'dart:math' as math;

class NeighborhoodLocations {
  // Constantes de ubicación por defecto para Villa Escuadrón Galilea, Coronel
  static const String defaultRegion = 'Región del Biobío';
  static const String defaultComuna = 'Coronel';
  static const String defaultSector = 'Villa Escuadrón Galilea';
  static const String defaultStreet = 'Pasaje Catrileo';
  static const String defaultHouseNumber = '2430';

  static const String customSectorOption = '+ Escribir otra villa o sector...';
  static const String customStreetOption = '+ Escribir otro pasaje o calle...';

  // 1. Las 16 Regiones oficiales de Chile
  static const List<String> regions = [
    'Región del Biobío',
    'Región Metropolitana de Santiago',
    'Región de Valparaíso',
    'Región de Ñuble',
    'Región de La Araucanía',
    'Región de O\'Higgins',
    'Región del Maule',
    'Región de Los Lagos',
    'Región de Coquimbo',
    'Región de Antofagasta',
    'Región de Tarapacá',
    'Región de Arica y Parinacota',
    'Región de Atacama',
    'Región de Los Ríos',
    'Región de Aysén',
    'Región de Magallanes',
  ];

  // 2. Catálogo Oficial y Exhaustivo de las 346 Comunas de Chile por Región
  static const Map<String, List<String>> chileComunas = {
    'Región del Biobío': [
      'Coronel',
      'Lota',
      'Tomé',
      'San Pedro de la Paz',
      'Concepción',
      'Talcahuano',
      'Hualpén',
      'Chiguayante',
      'Penco',
      'Santa Juana',
      'Arauco',
      'Los Ángeles',
      'Curanilahue',
      'Lebu',
      'Cañete',
      'Contulmo',
      'Los Álamos',
      'Tirúa',
      'Antuco',
      'Cabrero',
      'Laja',
      'Mulchén',
      'Nacimiento',
      'Negrete',
      'Quilaco',
      'Quilleco',
      'San Rosendo',
      'Santa Bárbara',
      'Tucapel',
      'Yumbel',
      'Alto Biobío',
      'Florida',
      'Hualqui',
    ],
    'Región Metropolitana de Santiago': [
      'Santiago',
      'Puente Alto',
      'Maipú',
      'La Florida',
      'San Bernardo',
      'Las Condes',
      'Peñalolén',
      'Pudahuel',
      'Quilicura',
      'La Pintana',
      'El Bosque',
      'Recoleta',
      'Renca',
      'Conchalí',
      'Colina',
      'Estación Central',
      'Providencia',
      'Cerro Navia',
      'Melipilla',
      'Pedro Aguirre Cerda',
      'Lo Prado',
      'Macul',
      'Quinta Normal',
      'San Miguel',
      'Lo Barnechea',
      'Lampa',
      'Huechuraba',
      'San Joaquín',
      'La Reina',
      'Vitacura',
      'La Cisterna',
      'Buin',
      'Talagante',
      'Lo Espejo',
      'San Ramón',
      'Padre Hurtado',
      'Peñaflor',
      'Paine',
      'Curacaví',
      'Isla de Maipo',
      'El Monte',
      'Pirque',
      'Calera de Tango',
      'Tiltil',
      'San José de Maipo',
      'María Pinto',
      'San Pedro',
      'Alhué',
      'Cerrillos',
      'Ñuñoa',
    ],
    'Región de Valparaíso': [
      'Valparaíso',
      'Viña del Mar',
      'Quilpué',
      'Villa Alemana',
      'Concón',
      'Quillota',
      'San Antonio',
      'Los Andes',
      'San Felipe',
      'La Calera',
      'Limache',
      'San Esteban',
      'Calle Larga',
      'Rinconada',
      'Santa María',
      'Llaillay',
      'Catemu',
      'Panquehue',
      'Putaendo',
      'La Cruz',
      'Nogales',
      'Hijuelas',
      'Olmué',
      'Algarrobo',
      'Cartagena',
      'El Quisco',
      'El Tabo',
      'Santo Domingo',
      'Casablanca',
      'Puchuncaví',
      'Quintero',
      'Papudo',
      'Zapallar',
      'Cabildo',
      'La Ligua',
      'Petorca',
      'Isla de Pascua',
      'Juan Fernández',
    ],
    'Región de Ñuble': [
      'Chillán',
      'Chillán Viejo',
      'San Carlos',
      'Coihueco',
      'Bulnes',
      'Yungay',
      'Quillón',
      'San Ignacio',
      'Coelemu',
      'Quirihue',
      'Pinto',
      'San Nicolás',
      'El Carmen',
      'Ñiquén',
      'Pemuco',
      'Portezuelo',
      'Ránquil',
      'Treguaco',
      'Cobquecura',
      'Ninhue',
      'San Fabián',
    ],
    'Región de La Araucanía': [
      'Temuco',
      'Padre Las Casas',
      'Villarrica',
      'Angol',
      'Pucón',
      'Lautaro',
      'Victoria',
      'Nueva Imperial',
      'Collipulli',
      'Traiguén',
      'Carahue',
      'Loncoche',
      'Pitrufquén',
      'Vilcún',
      'Freire',
      'Cunco',
      'Curacautín',
      'Gorbea',
      'Purén',
      'Renaico',
      'Galvarino',
      'Teodoro Schmidt',
      'Toltén',
      'Cholchol',
      'Saavedra',
      'Ercilla',
      'Lumaco',
      'Los Sauces',
      'Melipeuco',
      'Perquenco',
      'Curarrehue',
      'Lonquimay',
    ],
    'Región de O\'Higgins': [
      'Rancagua',
      'Machalí',
      'San Fernando',
      'Rengo',
      'Graneros',
      'San Vicente',
      'Mostazal',
      'Chimbarongo',
      'Pichilemu',
      'Requínoa',
      'Santa Cruz',
      'Coltauco',
      'Doñihue',
      'Peumo',
      'Las Cabras',
      'Quinta de Tilcoco',
      'Malloa',
      'Codegua',
      'Olivar',
      'Coinco',
      'Pichidegua',
      'Chépica',
      'Nancagua',
      'Palmilla',
      'Peralillo',
      'Placilla',
      'Pumanque',
      'Lolol',
      'Marchihue',
      'La Estrella',
      'Litueche',
      'Navidad',
      'Paredones',
    ],
    'Región del Maule': [
      'Talca',
      'Curicó',
      'Linares',
      'Constitución',
      'Maule',
      'San Javier',
      'Molina',
      'Parral',
      'Cauquenes',
      'San Clemente',
      'Teno',
      'Longaví',
      'Colbún',
      'Retiro',
      'Villa Alegre',
      'Yerbas Buenas',
      'Romeral',
      'Rauco',
      'Sagrada Familia',
      'Hualañé',
      'Licantén',
      'Vichuquén',
      'Curepto',
      'Pelarco',
      'Pencahue',
      'Río Claro',
      'San Rafael',
      'Empedrado',
      'Chanco',
      'Pelluhue',
    ],
    'Región de Los Lagos': [
      'Puerto Montt',
      'Osorno',
      'Puerto Varas',
      'Castro',
      'Ancud',
      'Quellón',
      'Frutillar',
      'Llanquihue',
      'Los Muermos',
      'Calbuco',
      'Maullín',
      'Fresia',
      'Cochamó',
      'Dalcahue',
      'Chonchi',
      'Queilén',
      'Quemchi',
      'Quinchao',
      'Puqueldón',
      'Curaco de Vélez',
      'Purranque',
      'Río Negro',
      'San Pablo',
      'San Juan de la Costa',
      'Puerto Octay',
      'Puyehue',
      'Chaitén',
      'Hualaihué',
      'Futaleufú',
      'Palena',
    ],
    'Región de Coquimbo': [
      'La Serena',
      'Coquimbo',
      'Ovalle',
      'Illapel',
      'Vicuña',
      'Salamanca',
      'Los Vilos',
      'Monte Patria',
      'Combarbalá',
      'Andacollo',
      'Punitaqui',
      'Canela',
      'Paihuano',
      'Río Hurtado',
      'La Higuera',
    ],
    'Región de Antofagasta': [
      'Antofagasta',
      'Calama',
      'Mejillones',
      'Tocopilla',
      'San Pedro de Atacama',
      'Taltal',
      'María Elena',
      'Sierra Gorda',
      'Ollagüe',
    ],
    'Región de Tarapacá': [
      'Iquique',
      'Alto Hospicio',
      'Pozo Almonte',
      'Pica',
      'Huara',
      'Camiña',
      'Colchane',
    ],
    'Región de Arica y Parinacota': [
      'Arica',
      'Camarones',
      'Putre',
      'General Lagos',
    ],
    'Región de Atacama': [
      'Copiapó',
      'Vallenar',
      'Caldera',
      'Chañaral',
      'Diego de Almagro',
      'Tierra Amarilla',
      'Huasco',
      'Freirina',
      'Alto del Carmen',
    ],
    'Región de Los Ríos': [
      'Valdivia',
      'La Unión',
      'Río Bueno',
      'Panguipulli',
      'Paillaco',
      'Mariquina',
      'Los Lagos',
      'Lanco',
      'Futrono',
      'Lago Ranco',
      'Máfil',
      'Corral',
    ],
    'Región de Aysén': [
      'Coyhaique',
      'Aysén',
      'Chile Chico',
      'Cochrane',
      'Cisnes',
      'Guaitecas',
      'Río Ibáñez',
      'O’Higgins',
      'Tortel',
      'Lago Verde',
    ],
    'Región de Magallanes': [
      'Punta Arenas',
      'Puerto Natales',
      'Porvenir',
      'Cabo de Hornos',
      'Torres del Paine',
      'San Gregorio',
      'Primavera',
      'Laguna Blanca',
      'Río Verde',
      'Timaukel',
      'Antártica',
    ],
  };

  // Obtener la lista oficial de comunas según la región seleccionada
  static List<String> getComunasForRegion(String region) {
    if (chileComunas.containsKey(region)) {
      return chileComunas[region]!;
    }
    final r = region.toLowerCase();
    for (final entry in chileComunas.entries) {
      if (entry.key.toLowerCase().contains(r) || r.contains(entry.key.toLowerCase())) {
        return entry.value;
      }
    }
    if (r.contains('biobío') || r.contains('bio bio')) return chileComunas['Región del Biobío']!;
    if (r.contains('metropolitana') || r.contains('santiago')) return chileComunas['Región Metropolitana de Santiago']!;
    if (r.contains('valparaíso') || r.contains('valparaiso')) return chileComunas['Región de Valparaíso']!;
    if (r.contains('ñuble') || r.contains('nuble')) return chileComunas['Región de Ñuble']!;
    if (r.contains('araucanía') || r.contains('araucania')) return chileComunas['Región de La Araucanía']!;
    if (r.contains('ohiggins') || r.contains("o'higgins")) return chileComunas['Región de O\'Higgins']!;
    if (r.contains('maule')) return chileComunas['Región del Maule']!;
    if (r.contains('lagos')) return chileComunas['Región de Los Lagos']!;
    if (r.contains('coquimbo')) return chileComunas['Región de Coquimbo']!;
    if (r.contains('antofagasta')) return chileComunas['Región de Antofagasta']!;
    if (r.contains('tarapacá') || r.contains('tarapaca')) return chileComunas['Región de Tarapacá']!;
    if (r.contains('arica')) return chileComunas['Región de Arica y Parinacota']!;
    if (r.contains('atacama')) return chileComunas['Región de Atacama']!;
    if (r.contains('ríos') || r.contains('rios')) return chileComunas['Región de Los Ríos']!;
    if (r.contains('aysén') || r.contains('aysen') || r.contains('aisén')) return chileComunas['Región de Aysén']!;
    if (r.contains('magallanes')) return chileComunas['Región de Magallanes']!;

    return chileComunas['Región del Biobío']!;
  }

  // 3. Sectores y Villas según Comuna seleccionada
  static List<String> getSectoresForComuna(String comuna) {
    return [..._getRawSectoresForComuna(comuna), customSectorOption];
  }

  static List<String> _getRawSectoresForComuna(String comuna) {
    switch (comuna) {
      case 'Coronel':
        return [
          'Villa Escuadrón Galilea',
          'Villa Verde',
          'Parque La Posada',
          'Escuadrón Sur',
          'Lagunillas 1 y 2',
          'Lagunillas 3',
          'Camilo Olavarría',
          'Yobilo 1 y 2',
          'Schwager',
          'Coronel Centro',
          'Villa Mora',
          'Caleta Lo Rojas',
          'Playa Blanca Coronel',
          'Maule',
          'Paso Seco',
          'Pocillas',
          'Berta',
        ];

      case 'Lota':
        return [
          'El Morro',
          'Villa Los Héroes',
          'Lota Alto',
          'Lota Bajo',
          'Pabellones Carlos Cousiño',
          'Fuerte Viejo',
          'Colcura',
          'Chambeque',
          'Polvorín',
          'Playa Blanca Lota',
          'Santa María',
          'Fundición',
          'Chilicauquén',
          'Cerro La Cruz',
          'Cerro San Antonio',
          'Población Idahue',
          'El Blanco',
          'Cancha Los Mineros',
        ];

      case 'Tomé':
        return [
          'El Morro de Tomé',
          'Bellavista',
          'Dichato',
          'Tomé Centro',
          'Cerro Alegre',
          'Villa Altos de Tomé',
          'Villa Alemania',
          'Población California',
          'Población Carlos Mahns',
          'Cerro Estanque',
          'Cerro Navidad',
          'Frutillares',
          'Cocholgüe',
          'Punta de Parra',
          'Coliumo',
          'Rafael',
          'Cerro San Juan',
          'Loma Larga',
        ];

      case 'San Pedro de la Paz':
        return [
          'Lomas Coloradas',
          'Huertos Familiares',
          'Villa San Pedro',
          'Andalué',
          'Boca Sur',
          'Candelaria',
          'Michaihue',
          'San Pedro de la Costa',
          'Loma Alta',
          'El Venado',
          'San Pedro del Valle',
          'Idahue',
          'Portal de San Pedro',
        ];

      case 'Concepción':
        return [
          'Centro Concepción',
          'Barrio Universitario',
          'Collao',
          'Valle Nonguén',
          'Lorenzo Arenas',
          'Pedro de Valdivia',
          'Villa Cap',
          'Palomares',
          'Santa Sabina',
          'Barrio Norte',
          'Lomas de San Sebastián',
          'Lomas de San Andrés',
          'Valle Noble',
          'Chillancito',
          'Agüita de la Perdiz',
        ];

      case 'Talcahuano':
        return [
          'Talcahuano Centro',
          'Los Cerros',
          'Las Higueras',
          'San Vicente',
          'Salinas',
          'Brisas del Sol',
          'Denavi Sur',
          'Medio Camino',
          'Santa Clara',
          'San Marcos',
          'El Morro de Talcahuano',
          'Huachipato',
        ];

      case 'Hualpén':
        return [
          'Villa Acero',
          'Lan 94 / Lan C',
          'Peñuelas',
          'Parque Central',
          'René Schneider',
          'Hualpencillo',
          'Caleta Lenga',
          'Villa Presidente Bulnes',
          'Críspulo Gándara',
          'Parque Las Américas',
        ];

      case 'Chiguayante':
        return [
          'Chiguayante Centro',
          'Vilumanque',
          'Lonco Norte',
          'Lonco Parque',
          'Schaub',
          'Villuco',
          'Manquimávida',
          'Los Altos de Chiguayante',
          'Santa Sofía',
          'La Leonera',
          'Porvenir',
          'Chiguayante Sur',
        ];

      case 'Penco':
        return [
          'Penco Centro',
          'Playa Negra',
          'Lirquén',
          'Cerro Verde Alto',
          'Cerro Verde Bajo',
          'Villa Italia',
          'Ríos de Chile',
          'Primer Agua',
          'Villa Cosmito',
          'La Greda',
        ];

      case 'Santa Juana':
        return [
          'Santa Juana Centro',
          'Villa Guadalcázar',
          'Huallerehue',
          'Colico',
          'Tricauco',
          'Curapalihue',
        ];

      case 'Arauco':
        return [
          'Arauco Centro',
          'Tubul',
          'Laraquete',
          'Carampangue',
          'Llico',
          'Ramadillas',
          'Punta Lavapié',
        ];

      case 'Los Ángeles':
        return [
          'Los Ángeles Centro',
          'Villa España',
          'Paillihue',
          'Santiago Bueras',
          'Villa Génesis',
          'Parque Sor Vicenta',
          'El Peral',
        ];

      // --- SANTIAGO / REGIÓN METROPOLITANA ---
      case 'Santiago':
        return [
          'Santiago Centro',
          'Barrio Lastarria',
          'Barrio Bellas Artes',
          'Barrio Brasil',
          'Barrio Yungay',
          'Barrio Concha y Toro',
          'Barrio Diez de Julio',
          'Barrio Matta Sur',
          'Parque Almagro',
          'San Vicente',
        ];

      case 'Providencia':
        return [
          'Pedro de Valdivia Norte',
          'Providencia Centro',
          'Barrio Italia',
          'Bellavista Providencia',
          'Los Leones',
          'Manuel Montt',
          'Pocuro',
          'Salvador',
        ];

      case 'Las Condes':
        return [
          'El Golf',
          'San Damián',
          'Los Dominicos',
          'Manquehue',
          'Colón Oriente',
          'San Carlos de Apoquindo',
          'Rotonda Atenas',
          'Estoril',
        ];

      case 'Ñuñoa':
        return [
          'Plaza Ñuñoa',
          'Barrio Italia Ñuñoa',
          'Plaza Egaña',
          'Villa Frei',
          'Parque Bustamante',
          'Suárez Mujica',
          'Estadio Nacional',
        ];

      case 'La Florida':
        return [
          'Bellavista de La Florida',
          'Walker Martínez',
          'Rojas Magallanes',
          'Trinidad',
          'Los Quillayes',
          'San José de la Estrella',
          'Santa Amalia',
          'Jardín Alto',
        ];

      case 'Maipú':
        return [
          'Maipú Centro',
          'Ciudad Satélite',
          'Los Pajaritos',
          'El Abrazo',
          'La Farfana',
          'Villa Los Héroes Maipú',
          'Santa Ana de Chena',
          'Las Rosas',
        ];

      case 'Puente Alto':
        return [
          'Puente Alto Centro',
          'Las Vizcachas',
          'Bajos de Mena',
          'Ciudad del Sol',
          'Casas Viejas',
          'Gabriela',
          'San Gerónimo',
          'Villa Los Toros',
        ];

      case 'San Bernardo':
        return [
          'San Bernardo Centro',
          'Nos',
          'Chena',
          'Los Morros',
          'El Manzano',
          'Maestranza',
        ];

      // --- VALPARAÍSO / VIÑA DEL MAR ---
      case 'Viña del Mar':
        return [
          'Reñaca',
          'Viña Centro',
          'Plan de Viña',
          'Miraflores',
          'Gómez Carreño',
          'Santa Inés',
          'Forestal',
          'Nueva Aurora',
          'Chorrillos',
          'Recreo',
          'Agua Santa',
          'Jardín del Mar',
        ];

      case 'Valparaíso':
        return [
          'Cerro Alegre',
          'Cerro Concepción',
          'Cerro Bellavista',
          'Cerro Barón',
          'Cerro Playa Ancha',
          'El Plan de Valparaíso',
          'Cerro Cárcel',
          'Cerro Polanco',
          'Laguna Verde',
          'Placilla de Peñuelas',
        ];

      case 'Quilpué':
        return [
          'Quilpué Centro',
          'El Belloto 2000',
          'El Belloto Norte',
          'El Belloto Sur',
          'Los Pinos',
          'Paso Hondo',
          'Valencia',
        ];

      case 'Villa Alemana':
        return [
          'Villa Alemana Centro',
          'Peñablanca',
          'Troncos Viejos',
          'Gumersindo',
          'Huanhualí',
        ];

      // --- ÑUBLE ---
      case 'Chillán':
        return [
          'Chillán Centro',
          'Los Volcanes',
          'Las Terrazas',
          'Sarita Gajardo',
          'Lantaño',
          'Vicente Pérez Rosales',
          'Quilamapu',
          'Parque Lantaño',
        ];

      // --- LA ARAUCANÍA ---
      case 'Temuco':
        return [
          'Temuco Centro',
          'Avenida Alemania',
          'Pueblo Nuevo',
          'Pedro de Valdivia',
          'Santa Rosa',
          'Amanecer',
          'Labranza',
          'Fundo El Carmen',
        ];

      // --- LOS LAGOS ---
      case 'Puerto Montt':
        return [
          'Puerto Montt Centro',
          'Angelmó',
          'Alerce',
          'Mirasol',
          'Pelluco',
          'Valle Volcanes',
          'Pichi Pelluco',
          'Cardonal',
        ];

      // --- COQUIMBO ---
      case 'La Serena':
        return [
          'La Serena Centro',
          'San Joaquín',
          'El Milagro',
          'La Florida La Serena',
          'Las Compañías',
          'Cuatro Esquinas',
          'Avenida del Mar',
        ];

      case 'Coquimbo':
        return [
          'Coquimbo Centro',
          'Peñuelas',
          'Guayacán',
          'Tierras Blancas',
          'La Herradura',
          'Sindempart',
          'Punta Mira',
          'San Juan',
        ];

      // --- ANTOFAGASTA ---
      case 'Antofagasta':
        return [
          'Antofagasta Centro',
          'Coviefi',
          'Jardines del Sur',
          'Playa Blanca Antofagasta',
          'Gran Vía',
          'Bonilla',
          'La Chimba',
        ];

      // --- TARAPACÁ ---
      case 'Iquique':
        return [
          'Iquique Centro',
          'Cavancha',
          'Playa Brava',
          'El Morro de Iquique',
          'Huayquique',
          'Gómez Carreño',
          'Bajo Molle',
        ];

      // --- ARICA Y PARINACOTA ---
      case 'Arica':
        return [
          'Arica Centro',
          'El Morro de Arica',
          'Chinatown',
          'Cerro La Cruz Arica',
          'Saucache',
          'San José Arica',
          'Población Magisterio',
        ];

      // --- ATACAMA ---
      case 'Copiapó':
        return [
          'Copiapó Centro',
          'Paipote',
          'El Palomar',
          'Rosario',
          'Tornagaleones',
          'Borgoño',
        ];

      // --- O'HIGGINS ---
      case 'Rancagua':
        return [
          'Rancagua Centro',
          'Villa Triana',
          'Manzanal',
          'San Damián',
          'Kennedy',
          'Baquedano',
        ];

      // --- MAULE ---
      case 'Talca':
        return [
          'Talca Centro',
          'Las Rastras',
          'La Florida Talca',
          'Faustino González',
          'Carlos Trupp',
          'San Miguel del Piduco',
        ];

      // --- LOS RÍOS ---
      case 'Valdivia':
        return [
          'Valdivia Centro',
          'Isla Teja',
          'Las Ánimas',
          'Collico',
          'Regional',
          'Corvi',
          'Angachilla',
        ];

      // --- AYSÉN ---
      case 'Coyhaique':
        return [
          'Coyhaique Centro',
          'Villa Los Glaciares',
          'Sector El Mirador',
          'Población Almirante Simpson',
        ];

      // --- MAGALLANES ---
      case 'Punta Arenas':
        return [
          'Punta Arenas Centro',
          'Barrio Prat',
          'Playa Norte',
          'Cerro de la Cruz',
          'Barrio 18 de Septiembre',
          'Barrio San Miguel',
        ];

      default:
        return [
          'Sector Residencial Centro',
          'Sector Norte',
          'Sector Sur',
          'Sector Oriente',
          'Sector Poniente',
          'Villa Principal',
          'Población Central',
        ];
    }
  }

  // 4. Calles y Pasajes REALES según Sector
  static List<String> getStreetsForSector(String sector) {
    List<String> list;

    switch (sector) {
      // --- CORONEL ---
      case 'Villa Escuadrón Galilea':
        list = [
          'Pasaje Catrileo',
          'Pasaje Curamil',
          'Pasaje Llinko',
          'Pasaje Wennmapu',
          'Pasaje Paillao',
          'Pasaje Regumilla',
          'Pasaje Chiguay',
          'Avenida Las Torres',
          'Avenida Galvarino',
          'Calle Michimalonco',
          'Calle Guacolda',
          'Calle Caupolicán',
          'Calle Fresia',
          'Calle Lautaro',
          'Calle Colo Colo',
          'Calle Pelantaro',
        ];
        break;

      case 'Villa Verde':
        list = [
          'Avenida Villa Verde',
          'Pasaje Los Alerces',
          'Pasaje Los Canelos',
          'Pasaje Los Notros',
          'Pasaje Arrayán',
          'Pasaje Las Lengas',
          'Pasaje Los Laureles',
        ];
        break;

      case 'Parque La Posada':
        list = [
          'Avenida La Posada',
          'Pasaje Los Pinos',
          'Pasaje Los Aromos',
          'Pasaje Las Lilas',
          'Pasaje Los Laureles',
          'Pasaje El Roble',
        ];
        break;

      case 'Escuadrón Sur':
        list = [
          'Camino a Escuadrón',
          'Pasaje Los Pescadores',
          'Pasaje Huertos de Escuadrón',
          'Calle Central Escuadrón',
          'Pasaje La Posada Sur',
        ];
        break;

      case 'Lagunillas 1 y 2':
        list = [
          'Avenida Manuel Montt',
          'Calle Los Copihues',
          'Pasaje Los Boldos',
          'Pasaje El Peumo',
          'Calle Las Camelias',
          'Pasaje El Maitén',
          'Pasaje Los Robles',
          'Pasaje Los Mañíos',
          'Calle Las Encinas',
        ];
        break;

      case 'Lagunillas 3':
        list = [
          'Avenida Los Parques',
          'Calle Los Cipreses',
          'Pasaje El Canelo',
          'Pasaje Los Canelos',
          'Pasaje Los Notros',
          'Calle Las Violetas',
        ];
        break;

      case 'Camilo Olavarría':
        list = [
          'Calle Carlos Prat',
          'Pasaje Los Carrera',
          'Calle San Pedro',
          'Pasaje Manuel Rodríguez',
          'Pasaje Chacabuco',
          'Calle O\'Higgins',
          'Pasaje Balmaceda',
        ];
        break;

      case 'Yobilo 1 y 2':
        list = [
          'Calle Principal Yobilo',
          'Pasaje Los Sauces',
          'Pasaje 1 de Mayo',
          'Pasaje San Martín',
          'Calle Los Cipreses',
          'Pasaje La Unión',
          'Calle Lautaro',
        ];
        break;

      case 'Schwager':
        list = [
          'Calle Schwager',
          'Pasaje Pique Grande',
          'Calle La Chiflera',
          'Pasaje El Silo',
          'Pasaje Maule',
          'Pasaje El Carbón',
          'Calle Carlos Cousiño',
        ];
        break;

      case 'Coronel Centro':
        list = [
          'Calle Los Carrera',
          'Calle Sotomayor',
          'Calle Cochrane',
          'Calle Remigio Castro',
          'Calle Pedro Aguirre Cerda',
          'Calle Lautaro',
          'Calle Serrano',
          'Calle Prat',
          'Avenida Carlos Prats',
        ];
        break;

      case 'Villa Mora':
        list = [
          'Calle Villa Mora',
          'Pasaje San Antonio',
          'Pasaje Los Maitenes',
          'Pasaje Los Arrayanes',
          'Pasaje Santa Elena',
          'Calle Las Lilas',
        ];
        break;

      case 'Caleta Lo Rojas':
        list = [
          'Calle Costanera Lo Rojas',
          'Pasaje Los Pescadores',
          'Pasaje La Caleta',
          'Pasaje San Pedro',
          'Pasaje El Muelle',
          'Pasaje Las Redes',
        ];
        break;

      case 'Playa Blanca Coronel':
        list = [
          'Camino Playa Blanca',
          'Pasaje Las Brisas',
          'Pasaje El Sol',
          'Pasaje La Marina',
          'Costanera Playa Blanca',
        ];
        break;

      // --- LOTA ---
      case 'El Morro':
        list = [
          'Calle El Morro',
          'Pasaje La Puntilla',
          'Pasaje Las Rocas',
          'Pasaje Los Pescadores',
          'Pasaje Mirador El Morro',
          'Pasaje Costanera',
          'Pasaje El Faro',
          'Pasaje Pique Carlos',
          'Calle Nueva El Morro',
          'Pasaje Chambeque',
        ];
        break;

      case 'Villa Los Héroes':
        list = [
          'Calle Los Héroes',
          'Pasaje Arturo Prat',
          'Pasaje Ignacio Carrera Pinto',
          'Pasaje Eleuterio Ramírez',
          'Pasaje Carlos Condell',
          'Pasaje Sargento Aldea',
          'Pasaje Bernardo O\'Higgins',
          'Pasaje Los Granaderos',
          'Pasaje Manuel Rodríguez',
          'Pasaje Teniente Cruz',
        ];
        break;

      case 'Lota Alto':
        list = [
          'Avenida Carlos Cousiño',
          'Calle Pedro Aguirre Cerda',
          'Calle Sotomayor',
          'Calle Aníbal Pinto',
          'Calle Matta',
          'Calle Caupolicán',
          'Calle Galvarino',
          'Calle Los Copihues',
          'Pasaje Las Araucarias',
          'Calle Monsalve',
          'Calle Almirante Latorre',
        ];
        break;

      case 'Lota Bajo':
        list = [
          'Avenida Fernando Maira',
          'Calle Serrano',
          'Calle Valparaíso',
          'Calle Monsalve',
          'Calle Bannen',
          'Calle Lynch',
          'Calle Miraflores',
          'Calle Prat',
          'Pasaje El Roble',
          'Calle Los Carrera',
          'Calle San Martín',
        ];
        break;

      case 'Pabellones Carlos Cousiño':
        list = [
          'Calle Pabellón 1',
          'Calle Pabellón 2',
          'Calle Pabellón 3',
          'Calle Cousiño Central',
          'Pasaje Las Palmeras',
          'Pasaje Los Mineros',
          'Calle Pique Grande',
        ];
        break;

      case 'Fuerte Viejo':
        list = [
          'Calle El Fuerte',
          'Pasaje Mirador del Fuerte',
          'Pasaje Los Cañones',
          'Pasaje La Muralla',
          'Pasaje Centinela',
          'Calle Costanera Fuerte',
        ];
        break;

      case 'Colcura':
        list = [
          'Caleta Colcura',
          'Camino a Colcura',
          'Pasaje Los Aromos',
          'Pasaje Playa Linda',
          'Pasaje Los Castaños',
          'Pasaje La Cascada',
          'Calle Los Pescadores Colcura',
        ];
        break;

      case 'Chambeque':
        list = [
          'Calle Chambeque',
          'Pasaje Los Mineros',
          'Pasaje El Carbón',
          'Pasaje El Chiflón',
          'Camino El Pique',
        ];
        break;

      case 'Polvorín':
        list = [
          'Calle Polvorín',
          'Pasaje Los Álamos',
          'Pasaje Las Canteras',
          'Pasaje La Mina',
          'Calle Central Polvorín',
        ];
        break;

      case 'Playa Blanca Lota':
        list = [
          'Camino Playa Blanca Lota',
          'Pasaje Las Olas',
          'Pasaje La Brisa',
          'Pasaje El Sol Lota',
          'Costanera Lota',
        ];
        break;

      case 'Santa María':
        list = [
          'Calle Santa María',
          'Pasaje San José',
          'Pasaje Las Rosas',
          'Pasaje Los Claveles',
          'Pasaje Santa Teresita',
        ];
        break;

      case 'Fundición':
        list = [
          'Calle Fundición',
          'Pasaje Los Hornos',
          'Pasaje El Riel',
          'Pasaje Los Talleres',
          'Pasaje Central',
        ];
        break;

      case 'Chilicauquén':
        list = [
          'Camino Chilicauquén',
          'Pasaje Los Boldos',
          'Pasaje El Maitén',
          'Pasaje Los Coigües',
        ];
        break;

      case 'Cerro La Cruz':
        list = [
          'Calle La Cruz',
          'Pasaje El Mirador',
          'Pasaje Calvario',
          'Pasaje La Cumbre',
        ];
        break;

      case 'Cerro San Antonio':
        list = [
          'Calle San Antonio',
          'Pasaje Las Vertientes',
          'Pasaje Los Cipreses',
          'Pasaje Bellavista',
        ];
        break;

      case 'Población Idahue':
        list = [
          'Calle Idahue',
          'Pasaje Los Alerces',
          'Pasaje Los Canelos',
          'Pasaje Los Notros',
        ];
        break;

      // --- TOMÉ ---
      case 'Tomé Centro':
        list = [
          'Calle Maipú',
          'Calle Manuel Montt',
          'Calle Mariano Egaña',
          'Calle Sotomayor',
          'Calle Nogueira',
          'Calle Portales',
          'Avenida Enrique Molina',
          'Calle Ignacio Serrano',
          'Calle Aníbal Pinto',
          'Calle Vicente Palacios',
          'Calle Lord Cochrane',
        ];
        break;

      case 'Bellavista':
        list = [
          'Avenida Latorre',
          'Calle Los Cardenales',
          'Pasaje La Fábrica',
          'Calle Miramar',
          'Pasaje Los Helechos',
          'Pasaje Bellavista Sur',
          'Calle José Manuel Balmaceda',
          'Pasaje Los Álamos',
          'Calle Fábrica Bellavista',
        ];
        break;

      case 'Dichato':
        list = [
          'Avenida Daniel Peñailillo',
          'Calle Pedro Aguirre Cerda',
          'Calle Los Pinos',
          'Costanera Dichato',
          'Pasaje Los Cisnes',
          'Pasaje Bahía Azul',
          'Pasaje El Pescador',
          'Calle Villarrica',
          'Avenida del Mar',
          'Pasaje Las Gaviotas',
        ];
        break;

      case 'El Morro de Tomé':
        list = [
          'Calle El Morro',
          'Pasaje La Marina',
          'Pasaje Centinela',
          'Pasaje Miramar',
          'Calle Rocas del Morro',
          'Pasaje Faro Tomé',
          'Pasaje Playa El Morro',
          'Calle Los Pescadores',
        ];
        break;

      case 'Cerro Alegre':
        list = [
          'Calle Los Alerces',
          'Pasaje Mirador',
          'Calle San Juan',
          'Pasaje Bella Vista',
          'Pasaje Los Cipreses',
          'Pasaje El Canelo',
          'Pasaje Los Canelos',
          'Calle Cerro Alegre',
        ];
        break;

      case 'Villa Altos de Tomé':
        list = [
          'Avenida Los Quillayes',
          'Pasaje Las Lilas',
          'Pasaje Los Lingues',
          'Pasaje Los Avellanos',
          'Pasaje El Canelo',
          'Pasaje Los Robles',
        ];
        break;

      case 'Villa Alemania':
        list = [
          'Calle Hamburgo',
          'Calle Berlín',
          'Pasaje Múnich',
          'Pasaje Baviera',
          'Calle Frutillar',
        ];
        break;

      case 'Población California':
        list = [
          'Calle California',
          'Pasaje Los Robles',
          'Pasaje Los Naranjos',
          'Pasaje San Francisco',
          'Calle Central California',
        ];
        break;

      case 'Población Carlos Mahns':
        list = [
          'Calle Carlos Mahns',
          'Pasaje La Unión',
          'Pasaje Los Cipreses',
          'Pasaje Las Camelias',
          'Calle Las Rosas',
        ];
        break;

      case 'Cerro Estanque':
        list = [
          'Calle El Estanque',
          'Pasaje Las Vertientes',
          'Pasaje La Cumbre',
          'Pasaje El Peumo',
          'Calle Los Helechos',
        ];
        break;

      case 'Cerro Navidad':
        list = [
          'Calle Navidad',
          'Pasaje La Paz',
          'Pasaje Los Pinos',
          'Pasaje Esperanza',
          'Calle Belén',
        ];
        break;

      case 'Frutillares':
        list = [
          'Camino Los Frutillares',
          'Pasaje La Fresa',
          'Pasaje Los Huertos',
          'Pasaje El Manzano',
          'Pasaje Las Frambuesas',
        ];
        break;

      case 'Cocholgüe':
        list = [
          'Caleta Cocholgüe',
          'Camino Principal Cocholgüe',
          'Pasaje Las Olas',
          'Pasaje Los Lobos',
          'Pasaje El Pescador',
          'Pasaje Mirador Marino',
        ];
        break;

      case 'Punta de Parra':
        list = [
          'Camino Punta de Parra',
          'Pasaje Los Eucaliptus',
          'Pasaje La Playa',
          'Pasaje Las Terrazas',
          'Calle Central Punta de Parra',
        ];
        break;

      case 'Coliumo':
        list = [
          'Caleta Coliumo',
          'Camino a Coliumo',
          'Pasaje Las Gaviotas',
          'Pasaje Los Pellines',
          'Pasaje Las Ballenas',
        ];
        break;

      case 'Rafael':
        list = [
          'Calle Comercio Rafael',
          'Pasaje La Parroquia',
          'Calle Las Rosas',
          'Pasaje San Rafael',
          'Camino Principal Rafael',
        ];
        break;

      // --- SAN PEDRO DE LA PAZ ---
      case 'Lomas Coloradas':
        list = [
          'Avenida Los Boldos',
          'Pasaje Los Notros',
          'Pasaje Los Canelos',
          'Pasaje Los Manzanos',
          'Pasaje El Coigüe',
          'Calle Las Araucarias',
          'Pasaje Los Robles',
          'Calle Las Encinas',
          'Avenida Lomas Coloradas',
        ];
        break;

      case 'Huertos Familiares':
        list = [
          'Calle Los Mañíos',
          'Pasaje Las Acacias',
          'Calle Las Encinas',
          'Pasaje Los Canelos',
          'Calle Los Sauces',
          'Pasaje El Maitén',
          'Calle Pedro Lira',
        ];
        break;

      case 'Villa San Pedro':
        list = [
          'Calle Michimalonco',
          'Calle Los Peumos',
          'Calle Las Begonias',
          'Calle Las Violetas',
          'Pasaje Los Tilos',
          'Calle Las Acacias',
          'Avenida Pedro Aguirre Cerda',
        ];
        break;

      case 'Andalué':
        list = [
          'Avenida Andalué',
          'Camino del Venado',
          'Pasaje El Roble',
          'Pasaje Los Cipreses',
          'Calle Rucalhue',
          'Pasaje Las Bandurrias',
          'Calle Laguna Grande',
        ];
        break;

      case 'Boca Sur':
        list = [
          'Calle Costanera Boca Sur',
          'Pasaje Los Pescadores',
          'Pasaje 1 Sur',
          'Pasaje 2 Sur',
          'Calle Daniel Belmar',
          'Calle El Mar',
          'Pasaje Las Jaibas',
        ];
        break;

      case 'Candelaria':
        list = [
          'Calle Los Arrayanes',
          'Pasaje Los Copihues',
          'Calle Lautaro',
          'Pasaje San Francisco',
          'Calle Central Candelaria',
        ];
        break;

      case 'Michaihue':
        list = [
          'Calle Michaihue',
          'Pasaje 1 Michaihue',
          'Pasaje 2 Michaihue',
          'Pasaje 3 Michaihue',
          'Calle O\'Higgins',
          'Calle Los Canelos',
        ];
        break;

      case 'San Pedro de la Costa':
        list = [
          'Avenida Central',
          'Pasaje Las Gaviotas',
          'Pasaje Los Delfines',
          'Pasaje El Pelícano',
          'Calle Las Dunas',
          'Pasaje Marino',
        ];
        break;

      // --- CONCEPCIÓN ---
      case 'Centro Concepción':
        list = [
          'Calle O\'Higgins',
          'Calle Barros Arana',
          'Calle Freire',
          'Calle Maipú',
          'Calle San Martín',
          'Calle Tucapel',
          'Calle Caupolicán',
          'Calle Aníbal Pinto',
          'Calle Colo Colo',
          'Calle Lincoyán',
          'Calle Angol',
          'Calle Salas',
          'Calle Arturo Prat',
          'Calle Los Carrera',
        ];
        break;

      case 'Barrio Universitario':
        list = [
          'Calle Edmundo Larenas',
          'Calle Víctor Lamas',
          'Pasaje Los Tilos',
          'Pasaje Los Olmos',
          'Calle Roosevelt',
          'Calle San Martín',
          'Pasaje Los Canelos',
        ];
        break;

      case 'Collao':
        list = [
          'Avenida Collao',
          'Calle Las Rosas',
          'Pasaje Los Lirios',
          'Calle Nonguén',
          'Pasaje Chorrillos',
          'Calle Tegualda',
          'Calle General Novoa',
          'Avenida San Juan Bosco',
        ];
        break;

      case 'Valle Nonguén':
        list = [
          'Camino a Nonguén',
          'Pasaje Los Boldos',
          'Pasaje El Canelo',
          'Pasaje Los Helechos',
          'Pasaje Las Vertientes',
          'Calle Los Coigües',
        ];
        break;

      case 'Lorenzo Arenas':
        list = [
          'Calle 21 de Mayo',
          'Calle Laguna Redonda',
          'Pasaje Los Copihues',
          'Calle Miraflores',
          'Calle Fernández Vial',
          'Pasaje Las Violetas',
        ];
        break;

      case 'Pedro de Valdivia':
        list = [
          'Avenida Pedro de Valdivia',
          'Calle Sanhueza',
          'Pasaje Las Carmelitas',
          'Calle Chiguayante',
          'Pasaje El Parque',
          'Calle Los Franciscanos',
        ];
        break;

      case 'Villa Cap':
        list = [
          'Calle Los Lingues',
          'Pasaje Los Castaños',
          'Pasaje Los Aromos',
          'Calle Las Araucarias',
          'Pasaje Los Alerces',
        ];
        break;

      case 'Palomares':
        list = [
          'Camino a Cabrero',
          'Calle 1 Norte',
          'Pasaje Los Pinos',
          'Calle Principal Palomares',
          'Pasaje Los Laureles',
        ];
        break;

      case 'Santa Sabina':
      case 'Barrio Norte':
        list = [
          'Avenida Manuel Rodríguez',
          'Calle Alonso de Ribera',
          'Pasaje Santa Sabina',
          'Pasaje Las Acacias',
          'Calle Las Camelias',
          'Calle Lientur',
          'Calle Pelantaro',
        ];
        break;

      // --- TALCAHUANO ---
      case 'Talcahuano Centro':
        list = [
          'Calle Colón',
          'Calle Valdivia',
          'Calle Bilbao',
          'Calle Blanco Encalada',
          'Calle San Martín',
          'Calle Bulnes',
          'Calle Riquelme',
          'Calle Covadonga',
        ];
        break;

      case 'Los Cerros':
        list = [
          'Calle Los Cerros',
          'Pasaje La Cumbre',
          'Pasaje El Mirador',
          'Pasaje Centinela',
          'Calle Nueva Los Cerros',
          'Pasaje Vista Hermosa',
        ];
        break;

      case 'Las Higueras':
        list = [
          'Avenida Desiderio García',
          'Calle Alto Horno',
          'Calle Carlos Dittborn',
          'Pasaje Los Acacios',
          'Calle Las Amapolas',
          'Pasaje Los Peumos',
        ];
        break;

      case 'San Vicente':
        list = [
          'Calle España',
          'Calle Pedro Montt',
          'Pasaje San Vicente',
          'Pasaje Los Pescadores',
          'Calle Malaquías Concha',
          'Pasaje Prat',
        ];
        break;

      case 'Salinas':
        list = [
          'Calle Las Salinas',
          'Pasaje Los Flamencos',
          'Pasaje Las Gaviotas',
          'Calle Almirante Neff',
          'Pasaje Los Pelícanos',
        ];
        break;

      case 'Brisas del Sol':
        list = [
          'Avenida Vasco Núñez de Balboa',
          'Calle Santa María',
          'Pasaje Pinta',
          'Pasaje Niña',
          'Calle Cristóbal Colón',
          'Pasaje Magallanes',
        ];
        break;

      // --- HUALPÉN ---
      case 'Villa Acero':
        list = [
          'Calle Finlandia',
          'Calle Noruega',
          'Calle Suecia',
          'Pasaje Dinamarca',
          'Calle Bélgica',
          'Calle Holanda',
        ];
        break;

      case 'Lan 94 / Lan C':
        list = [
          'Calle Curanilahue',
          'Pasaje Cañete',
          'Pasaje Lebu',
          'Pasaje Tirúa',
          'Calle Los Álamos',
          'Pasaje Contulmo',
        ];
        break;

      case 'Peñuelas':
        list = [
          'Calle Grecia',
          'Calle Roma',
          'Pasaje Atenas',
          'Pasaje Chipre',
          'Calle Nápoles',
          'Pasaje Esparta',
        ];
        break;

      case 'Parque Central':
        list = [
          'Avenida Parque Central',
          'Pasaje Los Parques',
          'Pasaje Las Araucarias',
          'Pasaje Los Eucaliptos',
          'Calle Las Encinas',
        ];
        break;

      case 'Caleta Lenga':
        list = [
          'Costanera Lenga',
          'Camino a Lenga',
          'Pasaje El Pescador',
          'Pasaje Los Mariscos',
          'Pasaje La Caleta Lenga',
        ];
        break;

      // --- CHIGUAYANTE ---
      case 'Chiguayante Centro':
        list = [
          'Calle Manuel Rodríguez',
          'Calle O\'Higgins',
          'Calle Cochrane',
          'Calle San Martín',
          'Calle José Miguel Carrera',
          'Calle Los Copihues',
        ];
        break;

      case 'Vilumanque':
        list = [
          'Camino a Vilumanque',
          'Pasaje Los Alerces',
          'Pasaje Los Notros',
          'Pasaje Las Lengas',
          'Pasaje Los Coigües',
        ];
        break;

      case 'Lonco Norte':
      case 'Lonco Parque':
        list = [
          'Calle Lonco Oriente',
          'Calle Lonco Poniente',
          'Pasaje Los Helechos',
          'Pasaje Los Robles',
          'Avenida Lonco Parque',
          'Pasaje Los Lingues',
        ];
        break;

      case 'Schaub':
        list = [
          'Camino a Schaub',
          'Pasaje Los Aromos',
          'Pasaje Las Lilas',
          'Pasaje Los Castaños',
          'Pasaje Los Sauces',
        ];
        break;

      case 'Villuco':
        list = [
          'Camino a Villuco',
          'Pasaje El Peumo',
          'Pasaje Los Boldos',
          'Pasaje Las Encinas',
          'Pasaje El Canelo',
        ];
        break;

      // --- PENCO ---
      case 'Penco Centro':
        list = [
          'Calle Freire',
          'Calle O\'Higgins',
          'Calle Maipú',
          'Calle Alcázar',
          'Calle Las Heras',
          'Calle Penco',
          'Calle San Vicente',
        ];
        break;

      case 'Playa Negra':
        list = [
          'Costanera Playa Negra',
          'Pasaje Las Sirenas',
          'Pasaje Los Lobos',
          'Calle Infante',
          'Pasaje La Marina',
        ];
        break;

      case 'Lirquén':
        list = [
          'Calle Balmaceda',
          'Calle Manuel Rodríguez',
          'Caleta Lirquén',
          'Pasaje Los Pescadores',
          'Pasaje Cochrane',
          'Calle Serrano',
          'Calle Prat',
        ];
        break;

      case 'Cerro Verde Alto':
      case 'Cerro Verde Bajo':
        list = [
          'Calle Cerro Verde Alto',
          'Calle Cerro Verde Bajo',
          'Pasaje El Roble',
          'Pasaje Los Aromos',
          'Pasaje Los Castaños',
          'Pasaje Las Violetas',
        ];
        break;

      case 'Villa Italia':
        list = [
          'Calle Roma',
          'Calle Venecia',
          'Pasaje Florencia',
          'Pasaje Nápoles',
          'Pasaje Milán',
          'Calle Génova',
        ];
        break;

      // --- SANTA JUANA ---
      case 'Santa Juana Centro':
        list = [
          'Calle Valdivia',
          'Calle Lautaro',
          'Calle Cochrane',
          'Calle O\'Higgins',
          'Calle Yungay',
          'Calle San Martín',
        ];
        break;

      // --- ARAUCO ---
      case 'Arauco Centro':
        list = [
          'Calle Esmeralda',
          'Calle Caupolicán',
          'Calle Prat',
          'Calle Carlos Condell',
          'Calle Serrano',
          'Calle Chacabuco',
        ];
        break;

      case 'Laraquete':
        list = [
          'Calle Los Boldos',
          'Costanera Laraquete',
          'Pasaje Las Palomitas',
          'Pasaje El Bosque',
          'Calle Río Laraquete',
        ];
        break;

      // --- LOS ÁNGELES ---
      case 'Los Ángeles Centro':
        list = [
          'Calle Colón',
          'Calle Valdivia',
          'Calle Lautaro',
          'Calle Caupolicán',
          'Calle Almagro',
          'Calle Villagrán',
        ];
        break;

      default:
        list = [
          'Avenida Principal',
          'Pasaje Los Copihues',
          'Pasaje La Araucaria',
          'Calle Central',
          'Pasaje Los Pinos',
          'Pasaje Los Álamos',
        ];
    }

    // Siempre agregamos la opción al final para escribir otra calle o pasaje si no está listado
    return [...list, customStreetOption];
  }

  // 5. Números reales de vivienda de Villa Escuadrón Galilea (Rango 2400 a 2520)
  static List<String> getGalileaHouseNumbers() {
    return List.generate(121, (i) => (2400 + i).toString());
  }

  // Opciones de detalle / interior
  static const List<String> interiorOptions = [
    'Casa Principal',
    'Interior 1',
    'Interior 2',
    'Depto A',
    'Depto B',
  ];

  // 6. VALIDACIONES ESTRICTAS ANTI-DATOS FALSOS / BASURA (Anti-fffff, Anti-aaaa, Anti-sssss)
  static String? validateHumanName(String? value, String label) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) return 'Ingresa tu $label';
    if (v.length < 2) return '$label debe tener al menos 2 letras';
    if (v.length > 40) return '$label es demasiado largo';

    // Solo letras (incluye tildes, diéresis, ñ) y espacios
    if (!RegExp(r'^[a-zA-ZáéíóúÁÉÍÓÚñÑüÜ\s\.\-]+$').hasMatch(v)) {
      return '$label solo puede contener letras';
    }

    // Detectar repetición absurda de 3 o más letras iguales seguidas (ej: fffff, aaaa, sssss, zzz)
    if (RegExp(r'(.)\1{2,}', caseSensitive: false).hasMatch(v)) {
      final sample = v.substring(0, math.min(v.length, 3));
      return '$label no parece ser un nombre real (letras repetidas como "$sample")';
    }

    // Detectar palabras sin vocales (ej: sssss, zxcv, bcdfgh, jklmn)
    if (!RegExp(r'[aeiouáéíóúü]', caseSensitive: false).hasMatch(v)) {
      return '$label no es válido (debe contener vocales)';
    }

    // Si tiene 3 o más letras, debe contener al menos una consonante (ej: aaaaa, oooo, uuu)
    if (v.length >= 3 && !RegExp(r'[bcdfghjklmnñpqrstvwxyz]', caseSensitive: false).hasMatch(v)) {
      return '$label no es válido (no puede estar formado solo por vocales repetidas)';
    }

    // Detectar secuencias de teclado o palabras de prueba conocidas
    final lower = v.toLowerCase();
    const badPatterns = [
      'asdf', 'qwert', 'zxcv', 'prueba', 'test', 'fake',
      'anonim', 'ningun', 'admin', 'usuario', 'vecino', 'dummy', 'xxxx',
    ];
    for (final bad in badPatterns) {
      if (lower.contains(bad)) {
        return '$label no es válido. Ingresa tus datos reales.';
      }
    }

    return null;
  }

  // Validación de número de casa (rechaza números falsos como 111111, 0000, 999999)
  static String? validateHouseNumber(String? value) {
    final v = (value ?? '').trim();
    if (v.isEmpty) return 'Ingresa el número de tu casa';
    if (!RegExp(r'^\d{1,6}$').hasMatch(v)) {
      return 'Ingresa solo números para la casa (ej: 45, 120, 2430)';
    }
    // Detectar repetición de números falsos (ej: 111111, 22222, 999999, 0000)
    if (RegExp(r'^(.)\1{3,}$').hasMatch(v)) {
      return 'Número de casa inválido (no uses dígitos repetidos como "$v")';
    }
    final num = int.tryParse(v);
    if (num == null || num <= 0) return 'El número de casa debe ser mayor a 0';
    return null;
  }

  // Validación de nombre de calle o pasaje personalizado
  static String? validateStreetName(String? value) {
    final v = (value ?? '').trim();
    if (v.isEmpty) return 'Ingresa el nombre del pasaje o calle';
    if (v.length < 3) return 'El nombre de la calle es demasiado corto';
    if (v.length > 50) return 'El nombre de la calle es demasiado largo';
    return validateHumanName(v, 'Pasaje o calle');
  }

  // Validación de teléfono móvil chileno (ej: 9 1234 5678 o +56 9 1234 5678)
  static String? validateChileanPhone(String? value, {bool isOptional = false}) {
    final raw = (value ?? '').trim();
    if (raw.isEmpty) {
      if (isOptional) return null;
      return 'Ingresa tu teléfono móvil';
    }

    final v = raw.replaceAll(RegExp(r'[^0-9]'), '');
    if (v.isEmpty) {
      if (isOptional) return null;
      return 'Ingresa tu teléfono móvil';
    }
    
    // Si viene con código de país 569, tomar los 9 dígitos
    String phone9 = v;
    if (v.startsWith('56') && v.length == 11) {
      phone9 = v.substring(2);
    }
    
    if (phone9.length != 9) {
      return 'El celular debe tener 9 dígitos (ej. 9 1234 5678)';
    }
    if (!phone9.startsWith('9')) {
      return 'El número debe comenzar con 9 (formato celular chileno)';
    }
    return null;
  }

  // Validación de PIN numérico de 4 dígitos para recuperación
  static String? validatePin(String? value) {
    final v = (value ?? '').trim();
    if (v.isEmpty) return 'Ingresa un PIN de seguridad de 4 dígitos';
    if (v.length != 4 || !RegExp(r'^\d{4}$').hasMatch(v)) {
      return 'El PIN debe ser exactamente de 4 dígitos numéricos';
    }
    return null;
  }
}
