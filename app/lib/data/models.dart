/// Modelos simples respaldados por Map: sirven igual para SQLite y para el JSON
/// que se cifra y sube a Drive (un solo formato, sin duplicar lógica).

int nowMs() => DateTime.now().toUtc().millisecondsSinceEpoch;

class Person {
  Person({
    required this.id,
    this.firstName = '',
    this.lastName = '',
    this.birthDate,
    this.phone,
    this.email,
    this.occupation,
    this.maritalStatus,
    this.household,
    this.godRelation,
    this.spiritualState,
    this.personalBattles,
    this.environment,
    this.mentalNotes,
    this.strengths,
    this.consentStatus = 'pendiente',
    this.consentAt,
    int? updatedAt,
    this.deleted = false,
  }) : updatedAt = updatedAt ?? nowMs();

  final String id;
  String firstName, lastName;
  String? birthDate, phone, email, occupation, maritalStatus, household;
  String? godRelation, spiritualState, personalBattles, environment, mentalNotes, strengths;
  String consentStatus;
  int? consentAt;
  int updatedAt;
  bool deleted;

  String get fullName => '$firstName $lastName'.trim();

  int? get age {
    final d = birthDate == null ? null : DateTime.tryParse(birthDate!);
    if (d == null) return null;
    final n = DateTime.now();
    var a = n.year - d.year;
    if (n.month < d.month || (n.month == d.month && n.day < d.day)) a--;
    return a;
  }

  bool get isMinor => (age ?? 99) < 18;

  Map<String, Object?> toMap() => {
        'id': id,
        'first_name': firstName,
        'last_name': lastName,
        'birth_date': birthDate,
        'phone': phone,
        'email': email,
        'occupation': occupation,
        'marital_status': maritalStatus,
        'household': household,
        'god_relation': godRelation,
        'spiritual_state': spiritualState,
        'personal_battles': personalBattles,
        'environment': environment,
        'mental_notes': mentalNotes,
        'strengths': strengths,
        'consent_status': consentStatus,
        'consent_at': consentAt,
        'updated_at': updatedAt,
        'deleted': deleted ? 1 : 0,
      };

  factory Person.fromMap(Map<String, Object?> m) => Person(
        id: m['id'] as String,
        firstName: (m['first_name'] ?? '') as String,
        lastName: (m['last_name'] ?? '') as String,
        birthDate: m['birth_date'] as String?,
        phone: m['phone'] as String?,
        email: m['email'] as String?,
        occupation: m['occupation'] as String?,
        maritalStatus: m['marital_status'] as String?,
        household: m['household'] as String?,
        godRelation: m['god_relation'] as String?,
        spiritualState: m['spiritual_state'] as String?,
        personalBattles: m['personal_battles'] as String?,
        environment: m['environment'] as String?,
        mentalNotes: m['mental_notes'] as String?,
        strengths: m['strengths'] as String?,
        consentStatus: (m['consent_status'] ?? 'pendiente') as String,
        consentAt: m['consent_at'] as int?,
        updatedAt: m['updated_at'] as int,
        deleted: (m['deleted'] ?? 0) == 1,
      );
}

const memoryKinds = {
  'sesion': 'Sesión de acompañamiento',
  'discipulado': 'Discipulado',
  'liderazgo': 'Reunión de liderazgo',
  'ministerio': 'Ministerio',
  'evento': 'Evento / fecha especial',
  'oracion': 'Oración y seguimiento',
};

class Memory {
  Memory({
    required this.id,
    required this.personId,
    int? occurredAt,
    this.kind = 'sesion',
    this.title = '',
    this.summary,
    this.body,
    this.godRelation,
    this.emotionalState,
    this.battles,
    this.environment,
    this.prayerPoints,
    this.agreements,
    this.nextSteps,
    this.followUpAt,
    this.tags,
    int? updatedAt,
    this.deleted = false,
  })  : occurredAt = occurredAt ?? nowMs(),
        updatedAt = updatedAt ?? nowMs();

  final String id, personId;
  int occurredAt;
  String kind, title;
  String? summary, body, godRelation, emotionalState, battles, environment;
  String? prayerPoints, agreements, nextSteps, tags;
  int? followUpAt;
  int updatedAt;
  bool deleted;

  Map<String, Object?> toMap() => {
        'id': id,
        'person_id': personId,
        'occurred_at': occurredAt,
        'kind': kind,
        'title': title,
        'summary': summary,
        'body': body,
        'god_relation': godRelation,
        'emotional_state': emotionalState,
        'battles': battles,
        'environment': environment,
        'prayer_points': prayerPoints,
        'agreements': agreements,
        'next_steps': nextSteps,
        'follow_up_at': followUpAt,
        'tags': tags,
        'updated_at': updatedAt,
        'deleted': deleted ? 1 : 0,
      };

  factory Memory.fromMap(Map<String, Object?> m) => Memory(
        id: m['id'] as String,
        personId: m['person_id'] as String,
        occurredAt: m['occurred_at'] as int,
        kind: (m['kind'] ?? 'sesion') as String,
        title: (m['title'] ?? '') as String,
        summary: m['summary'] as String?,
        body: m['body'] as String?,
        godRelation: m['god_relation'] as String?,
        emotionalState: m['emotional_state'] as String?,
        battles: m['battles'] as String?,
        environment: m['environment'] as String?,
        prayerPoints: m['prayer_points'] as String?,
        agreements: m['agreements'] as String?,
        nextSteps: m['next_steps'] as String?,
        followUpAt: m['follow_up_at'] as int?,
        tags: m['tags'] as String?,
        updatedAt: m['updated_at'] as int,
        deleted: (m['deleted'] ?? 0) == 1,
      );
}

class SearchHit {
  SearchHit({required this.kind, required this.id, required this.personId, required this.personName, required this.title, required this.snippet, required this.when});
  final String kind; // 'person' | 'memory'
  final String id, personId, personName, title, snippet;
  final int? when;
}
