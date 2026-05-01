# frozen_string_literal: true

# Seed data for Trato MVP — realistic Mexican independent workers
# Run with: bin/rails db:seed
# Reset and re-seed: bin/rails db:seed:replant
#
# Uses picsum.photos for placeholder images (free, no API key needed)

puts "🌱 Seeding Trato database..."

# ─── Clean slate ───────────────────────────────────────────────
puts "  Cleaning existing data..."
[SocialPost, Photo, Review, Transaction, Job, Appointment, WorkDay,
 Task, ProviderClient, Conversation, Message, ProviderCategory, Client, Provider].each(&:delete_all)

# ─── Helpers ───────────────────────────────────────────────────

def picsum_url(width, height, seed)
  "https://picsum.photos/seed/#{seed}/#{width}/#{height}"
end

# ─── Providers ─────────────────────────────────────────────────

providers_data = [
  {
    name: "Miguel García",
    phone: "5212291000001",
    city: "Veracruz",
    service_area: "Boca del Río, Centro, Mocambo, Costa Verde",
    base_price: 300,
    bio: "Electricista con 8 años de experiencia en Veracruz. Me especializo en instalaciones residenciales, reparación de cortos y mantenimiento de paneles eléctricos. Trabajo limpio, puntual y con garantía. Si tienes un problema eléctrico, yo te lo resuelvo.",
    email: "miguel.garcia@gmail.com",
    categories: [
      { name: "Electricista", slug: "electricista", primary: true },
      { name: "Instalaciones", slug: "instalaciones", primary: false }
    ],
    specialties: ["urgencias", "paneles-electricos", "instalaciones-residenciales"],
    work_photos: [
      { caption: "Panel eléctrico residencial instalado en Boca del Río", seed: "trato-elec-1" },
      { caption: "Instalación de contactos y apagadores en cocina", seed: "trato-elec-2" },
      { caption: "Reparación de corto circuito en sala", seed: "trato-elec-3" },
      { caption: "Cableado nuevo para ampliación de casa", seed: "trato-elec-4" }
    ]
  },
  {
    name: "Roberto Hernández",
    phone: "5212291000002",
    city: "Veracruz",
    service_area: "Centro, Zaragoza, Reforma, Las Américas",
    base_price: 350,
    bio: "Fontanero profesional con más de 12 años arreglando fugas, destapando tuberías y haciendo instalaciones hidráulicas. Trabajo rápido y limpio. Mis clientes me recomiendan porque siempre dejo todo funcionando al 100%.",
    email: "roberto.hdz@hotmail.com",
    categories: [
      { name: "Fontanero", slug: "fontanero", primary: true },
      { name: "Instalaciones hidráulicas", slug: "instalaciones-hidraulicas", primary: false }
    ],
    specialties: ["fugas", "destape-tuberias", "calentadores-solares"],
    work_photos: [
      { caption: "Reparación de fuga en baño principal", seed: "trato-font-1" },
      { caption: "Instalación de calentador solar en azotea", seed: "trato-font-2" },
      { caption: "Destape de tubería en cocina", seed: "trato-font-3" }
    ]
  },
  {
    name: "Carlos Martínez López",
    phone: "5212291000003",
    city: "Veracruz",
    service_area: "Boca del Río, Mocambo, Costa de Oro, Playa Linda",
    base_price: 400,
    bio: "Carpintero con 15 años de experiencia. Hago muebles a medida, closets, cocinas integrales y todo tipo de trabajo en madera. Me gusta que cada pieza quede perfecta. Si lo puedes imaginar, yo lo puedo construir.",
    email: nil,
    categories: [
      { name: "Carpintero", slug: "carpintero", primary: true },
      { name: "Muebles a medida", slug: "muebles-a-medida", primary: false }
    ],
    specialties: ["cocinas-integrales", "closets", "muebles-a-medida"],
    work_photos: [
      { caption: "Cocina integral de encino terminada", seed: "trato-carp-1" },
      { caption: "Closet empotrado con puertas corredizas", seed: "trato-carp-2" },
      { caption: "Librero de piso a techo en sala", seed: "trato-carp-3" },
      { caption: "Mesa de comedor de parota para 8 personas", seed: "trato-carp-4" },
      { caption: "Puerta principal de madera tallada", seed: "trato-carp-5" }
    ]
  },
  {
    name: "José Luis Ramírez",
    phone: "5212291000004",
    city: "Veracruz",
    service_area: "Centro, Zaragoza, Flores Magón, Ignacio de la Llave",
    base_price: 250,
    bio: "Albañil con 10 años de experiencia. Hago desde remodelaciones pequeñas hasta construcciones completas. Trabajo con block, tabique, concreto y acabados. Siempre entrego a tiempo y con buen acabado.",
    email: "jlramirez.albañil@gmail.com",
    categories: [
      { name: "Albañil", slug: "albanil", primary: true },
      { name: "Remodelaciones", slug: "remodelaciones", primary: false }
    ],
    specialties: ["remodelaciones", "acabados", "impermeabilizacion"],
    work_photos: [
      { caption: "Remodelación completa de baño", seed: "trato-alba-1" },
      { caption: "Construcción de barda perimetral", seed: "trato-alba-2" },
      { caption: "Piso de loseta en terraza", seed: "trato-alba-3" }
    ]
  },
  {
    name: "Ana Patricia Vega",
    phone: "5212291000005",
    city: "Veracruz",
    service_area: "Boca del Río, Costa Verde, Reserva Territorial",
    base_price: 500,
    bio: "Pintora profesional con 6 años de experiencia. Me especializo en interiores residenciales, acabados decorativos y restauración de fachadas. Trabajo limpio, protejo todos los muebles y siempre dejo todo impecable.",
    email: "ana.vega.pintora@gmail.com",
    categories: [
      { name: "Pintora", slug: "pintor", primary: true },
      { name: "Acabados decorativos", slug: "acabados-decorativos", primary: false }
    ],
    specialties: ["interiores", "fachadas", "acabados-decorativos"],
    work_photos: [
      { caption: "Pintura de sala con acabado texturizado", seed: "trato-pint-1" },
      { caption: "Restauración de fachada colonial", seed: "trato-pint-2" },
      { caption: "Acabado decorativo en recámara principal", seed: "trato-pint-3" },
      { caption: "Pintura exterior de casa completa", seed: "trato-pint-4" }
    ]
  },
  {
    name: "Fernando Díaz Morales",
    phone: "5212291000006",
    city: "Veracruz",
    service_area: "Centro, Las Américas, Reforma, Virginia",
    base_price: 350,
    bio: "Técnico en aire acondicionado y refrigeración con 9 años de experiencia. Instalo, reparo y doy mantenimiento a minisplits, aires centrales y refrigeradores comerciales. En Veracruz el calor no perdona, y yo tampoco con las fallas.",
    email: nil,
    categories: [
      { name: "Aire acondicionado", slug: "aire-acondicionado", primary: true },
      { name: "Refrigeración", slug: "refrigeracion", primary: false }
    ],
    specialties: ["minisplits", "aires-centrales", "refrigeracion-comercial"],
    work_photos: [
      { caption: "Instalación de minisplit inverter en oficina", seed: "trato-aire-1" },
      { caption: "Mantenimiento preventivo de aire central", seed: "trato-aire-2" },
      { caption: "Reparación de refrigerador comercial", seed: "trato-aire-3" }
    ]
  },
  {
    name: "Pedro Sánchez Ruiz",
    phone: "5212291000007",
    city: "Boca del Río",
    service_area: "Costa de Oro, Mocambo, Las Vegas, Floresta",
    base_price: 280,
    bio: "Cerrajero de confianza con 7 años de experiencia. Abro puertas, cambio chapas, instalo cerraduras de seguridad y hago duplicados de llaves. Disponible para emergencias las 24 horas.",
    email: "pedro.cerrajero@gmail.com",
    categories: [
      { name: "Cerrajero", slug: "cerrajero", primary: true }
    ],
    specialties: ["emergencias-24h", "cerraduras-seguridad", "puertas-blindadas"],
    work_photos: [
      { caption: "Instalación de cerradura de alta seguridad", seed: "trato-cerr-1" },
      { caption: "Cambio de chapa en puerta principal", seed: "trato-cerr-2" }
    ]
  },
  {
    name: "Laura Méndez Torres",
    phone: "5212291000008",
    city: "Veracruz",
    service_area: "Centro, Boca del Río, Alvarado",
    base_price: 450,
    bio: "Diseñadora de interiores y decoradora con 5 años de experiencia. Transformo espacios con buen gusto y presupuesto accesible. Desde una recámara hasta una remodelación completa, te ayudo a que tu casa se vea increíble.",
    email: "laura.mendez.deco@gmail.com",
    categories: [
      { name: "Decoradora", slug: "decorador", primary: true },
      { name: "Diseño de interiores", slug: "diseno-interiores", primary: false }
    ],
    specialties: ["remodelaciones-integrales", "espacios-pequenos", "iluminacion"],
    work_photos: [
      { caption: "Remodelación de sala estilo moderno", seed: "trato-deco-1" },
      { caption: "Diseño de recámara principal", seed: "trato-deco-2" },
      { caption: "Decoración de terraza con plantas", seed: "trato-deco-3" },
      { caption: "Iluminación decorativa en restaurante", seed: "trato-deco-4" }
    ]
  }
]

# ─── Clients ───────────────────────────────────────────────────

clients_data = [
  { name: "Mariana López", phone: "5212299000001" },
  { name: "Sofía Rodríguez", phone: "5212299000002" },
  { name: "Juan Pablo Torres", phone: "5212299000003" },
  { name: "Carmen Flores", phone: "5212299000004" },
  { name: "Ricardo Morales", phone: "5212299000005" },
  { name: "Gabriela Ortiz", phone: "5212299000006" },
  { name: "Alejandro Ruiz", phone: "5212299000007" },
  { name: "Patricia Vargas", phone: "5212299000008" },
  { name: "Daniel Castillo", phone: "5212299000009" },
  { name: "Isabel Guerrero", phone: "5212299000010" },
  { name: "Arturo Peña", phone: "5212299000011" },
  { name: "Lucía Jiménez", phone: "5212299000012" }
]

# ─── Review comments ───────────────────────────────────────────

review_comments = [
  "Excelente trabajo, muy puntual y profesional. Lo recomiendo al 100%.",
  "Llegó a tiempo, resolvió el problema rápido y dejó todo limpio. Muy recomendable.",
  "Muy buen trabajo. Explicó todo lo que iba a hacer antes de empezar. Precio justo.",
  "Súper recomendado. Hizo un trabajo impecable y el precio fue muy razonable.",
  "Muy profesional y amable. Resolvió el problema que otros no pudieron.",
  "Trabajo de primera calidad. Ya es mi técnico de confianza.",
  "Puntual, limpio y honesto con los precios. No busques más.",
  "Hizo un trabajo increíble. Mi esposa quedó encantada con el resultado.",
  "Muy responsable y cumplido. Entregó antes de lo prometido.",
  "Excelente servicio. Ya lo recomendé con todos mis vecinos.",
  "Buen trabajo, aunque tardó un poco más de lo esperado. El resultado valió la pena.",
  "Muy atento y resolvió todas mis dudas. Trabajo de calidad.",
  nil, # Some reviews without comment
  nil,
  "Quedé muy contenta con el resultado. Definitivamente lo vuelvo a llamar.",
  "Profesional de verdad. Se nota la experiencia.",
]

# ─── Create records ────────────────────────────────────────────

puts "  Creating clients..."
clients = clients_data.map do |data|
  Client.create!(data)
end

puts "  Creating providers with categories, photos, jobs, and reviews..."
providers_data.each_with_index do |data, provider_index|
  short_uuid = SecureRandom.hex(4)
  primary_cat = data[:categories].find { |c| c[:primary] }

  provider = Provider.create!(
    name: data[:name],
    phone: data[:phone],
    short_uuid: short_uuid,
    city: data[:city],
    service_area: data[:service_area],
    base_price: data[:base_price],
    bio: data[:bio],
    email: data[:email],
    active: true,
    onboarded_at: rand(90..365).days.ago
  )

  # Build slug after creating categories
  categories = data[:categories].map do |cat_data|
    ProviderCategory.create!(
      provider: provider,
      name: cat_data[:name],
      slug: cat_data[:slug],
      primary: cat_data[:primary]
    )
  end

  provider.update!(slug: provider.build_slug)

  # Profile photo
  Photo.create!(
    provider: provider,
    url: picsum_url(400, 400, "trato-profile-#{provider_index}"),
    caption: "Foto de perfil de #{provider.name}",
    profile_photo: true,
    category_tags: []
  )

  # Work photos
  data[:work_photos].each do |photo_data|
    Photo.create!(
      provider: provider,
      url: picsum_url(800, 600, photo_data[:seed]),
      caption: photo_data[:caption],
      profile_photo: false,
      category_tags: data[:specialties]
    )
  end

  # Assign 3-5 random clients to each provider
  assigned_clients = clients.sample(rand(3..5))
  assigned_clients.each do |client|
    ProviderClient.find_or_create_by!(provider: provider, client: client) do |pc|
      pc.last_contacted_at = rand(1..30).days.ago
    end
  end

  # Create 4-8 jobs per provider
  job_count = rand(4..8)
  provider_jobs = []
  job_count.times do |job_index|
    client = assigned_clients.sample
    service_date = rand(7..120).days.ago.to_date
    amount = [500, 800, 1200, 1500, 2000, 2500, 3000, 3500, 4500].sample
    status = %w[paid paid paid paid partial pending].sample
    paid_amount = status == "paid" ? amount : (status == "partial" ? (amount * 0.5).to_i : 0)

    job = Job.create!(
      provider: provider,
      client: client,
      description: [
        "Reparación de #{primary_cat[:name].downcase} en cocina",
        "Instalación completa en recámara principal",
        "Mantenimiento preventivo en oficina",
        "Trabajo de #{primary_cat[:name].downcase} en baño",
        "Remodelación parcial de sala",
        "Servicio de emergencia en domicilio",
        "Revisión y diagnóstico general",
        "Trabajo especializado en terraza"
      ].sample,
      amount: amount,
      paid_amount: paid_amount,
      status: status,
      payment_method: %w[cash transfer cash cash].sample,
      service_date: service_date
    )
    provider_jobs << job

    # Create income transaction for paid/partial jobs
    if paid_amount.positive?
      Transaction.create!(
        provider: provider,
        job: job,
        client: client,
        amount: paid_amount,
        transaction_type: "income",
        description: "Pago por #{job.description.downcase}",
        payment_method: job.payment_method,
        recorded_at: service_date.to_time + 8.hours,
        assigned_to: job.id.to_s
      )
    end
  end

  # Create 2-5 reviews per provider (only for paid jobs)
  paid_jobs = provider_jobs.select { |j| j.status == "paid" }
  review_count = [rand(2..5), paid_jobs.size].min
  reviewed_jobs = paid_jobs.sample(review_count)

  reviewed_jobs.each do |job|
    Review.create!(
      provider: provider,
      client: job.client,
      job: job,
      rating: [4, 4, 5, 5, 5, 5, 3, 5].sample,
      comment: review_comments.sample,
      verified: true
    )
  end

  # Create 1-2 expense transactions
  rand(1..2).times do
    Transaction.create!(
      provider: provider,
      amount: -[150, 250, 350, 500, 800].sample,
      transaction_type: "expense",
      description: [
        "Material: cable calibre 12",
        "Herramienta: llave stilson",
        "Material: tubo PVC 4 pulgadas",
        "Gasolina para traslados",
        "Material: pintura vinílica 19L",
        "Material: tornillos y taquetes",
        "Herramienta: disco de corte"
      ].sample,
      payment_method: "cash",
      recorded_at: rand(1..30).days.ago,
      assigned_to: "general"
    )
  end

  puts "    ✅ #{provider.name} — #{primary_cat[:name]} (#{data[:work_photos].size} fotos, #{review_count} reseñas)"
end

# ─── Summary ───────────────────────────────────────────────────

puts ""
puts "🎉 Seed complete!"
puts "   Providers:  #{Provider.count}"
puts "   Clients:    #{Client.count}"
puts "   Categories: #{ProviderCategory.count}"
puts "   Photos:     #{Photo.count} (#{Photo.where(profile_photo: true).count} profile + #{Photo.where(profile_photo: false).count} work)"
puts "   Jobs:       #{Job.count}"
puts "   Reviews:    #{Review.count}"
puts "   Transactions: #{Transaction.count}"
puts ""
puts "🌐 Visit http://localhost:3000 to see the homepage"
puts "📂 Visit http://localhost:3000/p/electricistas-en-veracruz to see the directory"
