/// Catalog module screens. The shell shows them as tabs: Katalog → Kayıtlar
/// ([ResourcesTab]) and Rezervasyonlar ([BookingsTab]), Müşteriler → Talepler ([LeadsTab]).
library;

export 'bookings_tab.dart' show BookingEditorSheet, BookingsTab, bookingSpan;
export 'leads_tab.dart' show LeadsTab, leadKindShortLabels;
export 'resource_editor_sheet.dart' show ResourceEditorSheet, openResourceEditor;
export 'resources_tab.dart' show ResourcesTab;
