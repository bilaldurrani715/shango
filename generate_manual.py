import docx
from docx import Document
from docx.shared import Inches, Pt, RGBColor
from docx.enum.text import WD_ALIGN_PARAGRAPH
from docx.enum.table import WD_TABLE_ALIGNMENT, WD_ALIGN_VERTICAL
from docx.oxml import OxmlElement, parse_xml
from docx.oxml.ns import nsdecls, qn

def set_cell_background(cell, fill_hex):
    tcPr = cell._tc.get_or_add_tcPr()
    shd = parse_xml(f'<w:shd {nsdecls("w")} w:fill="{fill_hex}"/>')
    tcPr.append(shd)

def set_cell_margins(cell, top=100, bottom=100, left=150, right=150):
    tcPr = cell._tc.get_or_add_tcPr()
    tcMar = parse_xml(f'''
        <w:tcMar {nsdecls("w")}>
            <w:top w:w="{top}" w:type="dxa"/>
            <w:bottom w:w="{bottom}" w:type="dxa"/>
            <w:left w:w="{left}" w:type="dxa"/>
            <w:right w:w="{right}" w:type="dxa"/>
        </w:tcMar>
    ''')
    tcPr.append(tcMar)

def add_screenshot_placeholder(doc, caption, description="Insert screenshot from your phone here"):
    table = doc.add_table(rows=1, cols=1)
    table.alignment = WD_TABLE_ALIGNMENT.CENTER
    table.autofit = False
    
    cell = table.cell(0, 0)
    cell.width = Inches(6.0)
    set_cell_background(cell, "F3F4F6")
    set_cell_margins(cell, top=200, bottom=200, left=250, right=250)
    
    # Border
    tcPr = cell._tc.get_or_add_tcPr()
    tcBorders = parse_xml(f'''
        <w:tcBorders {nsdecls("w")}>
            <w:top w:val="dashed" w:sz="12" w:space="0" w:color="9CA3AF"/>
            <w:left w:val="dashed" w:sz="12" w:space="0" w:color="9CA3AF"/>
            <w:bottom w:val="dashed" w:sz="12" w:space="0" w:color="9CA3AF"/>
            <w:right w:val="dashed" w:sz="12" w:space="0" w:color="9CA3AF"/>
        </w:tcBorders>
    ''')
    tcPr.append(tcBorders)
    
    p = cell.paragraphs[0]
    p.alignment = WD_ALIGN_PARAGRAPH.CENTER
    p.paragraph_format.space_before = Pt(8)
    p.paragraph_format.space_after = Pt(4)
    
    run_icon = p.add_run("📸 [ SCREENSHOT PLACEHOLDER ]\n")
    run_icon.bold = True
    run_icon.font.size = Pt(11)
    run_icon.font.color.rgb = RGBColor(0x37, 0x41, 0x51)
    
    run_caption = p.add_run(f"Figure: {caption}\n")
    run_caption.bold = True
    run_caption.font.size = Pt(10.5)
    run_caption.font.color.rgb = RGBColor(0x1F, 0x29, 0x37)
    
    run_desc = p.add_run(f"({description})")
    run_desc.italic = True
    run_desc.font.size = Pt(9.5)
    run_desc.font.color.rgb = RGBColor(0x6B, 0x72, 0x80)
    
    doc.add_paragraph().paragraph_format.space_after = Pt(6)

def build_manual():
    doc = Document()
    
    # Page setup
    for section in doc.sections:
        section.top_margin = Inches(0.8)
        section.bottom_margin = Inches(0.8)
        section.left_margin = Inches(0.8)
        section.right_margin = Inches(0.8)
        
    # Styles
    normal_style = doc.styles['Normal']
    normal_style.font.name = 'Segoe UI'
    normal_style.font.size = Pt(10.5)
    normal_style.font.color.rgb = RGBColor(0x1F, 0x29, 0x37)
    
    # Document Header Title
    title_p = doc.add_paragraph()
    title_p.paragraph_format.space_before = Pt(0)
    title_p.paragraph_format.space_after = Pt(2)
    title_run = title_p.add_run("ShanGo Ride-Booking Platform")
    title_run.bold = True
    title_run.font.size = Pt(24)
    title_run.font.color.rgb = RGBColor(0x11, 0x18, 0x27)
    
    subtitle_p = doc.add_paragraph()
    subtitle_p.paragraph_format.space_before = Pt(0)
    subtitle_p.paragraph_format.space_after = Pt(16)
    sub_run = subtitle_p.add_run("Complete Official User & Operations Manual (Passenger, Driver & Admin Console)")
    sub_run.font.size = Pt(13)
    sub_run.font.color.rgb = RGBColor(0xD9, 0x77, 0x06) # Amber/Gold
    sub_run.bold = True
    
    # Meta block
    meta_table = doc.add_table(rows=2, cols=2)
    meta_table.alignment = WD_TABLE_ALIGNMENT.CENTER
    meta_data = [
        [("Platform Version", "v1.0.0 (Production)"), ("Supported Platforms", "Android & iOS (Flutter)")],
        [("Backend Infrastructure", "Google Cloud Firebase & Firestore"), ("Push Notification Engine", "Firebase Cloud Messaging (FCM V1)")]
    ]
    for row_idx, row in enumerate(meta_table.rows):
        for col_idx, cell in enumerate(row.cells):
            set_cell_background(cell, "FEF3C7")
            set_cell_margins(cell, 80, 80, 120, 120)
            k, v = meta_data[row_idx][col_idx]
            p = cell.paragraphs[0]
            p.paragraph_format.space_before = Pt(0)
            p.paragraph_format.space_after = Pt(0)
            r1 = p.add_run(f"{k}: ")
            r1.bold = True
            r1.font.size = Pt(9.5)
            r2 = p.add_run(v)
            r2.font.size = Pt(9.5)
    
    doc.add_paragraph().paragraph_format.space_after = Pt(12)
    
    # -------------------------------------------------------------
    # PART 1: PASSENGER MANUAL
    # -------------------------------------------------------------
    h1 = doc.add_heading("Part 1: Passenger User Manual (Customer)", level=1)
    h1.paragraph_format.space_before = Pt(14)
    h1.paragraph_format.space_after = Pt(8)
    
    p = doc.add_paragraph("This section provides instructions for passengers on how to register, book local and intercity rides, negotiate prices, track drivers live, and submit ratings.")
    
    doc.add_heading("1.1 Registration & Authentication", level=2)
    p = doc.add_paragraph(
        "1. Open the ShanGo app on your mobile device.\n"
        "2. Choose your preferred sign-in method:\n"
        "   • Continue with Google: One-tap instant authentication.\n"
        "   • Email & Password: Sign in with existing credentials or register a new account.\n"
        "   • Phone Number: Instant verification via SMS.\n"
        "3. Select 'Passenger' as your default account profile role."
    )
    add_screenshot_placeholder(doc, "Passenger Login & Authentication Screen", "Place screenshot of the Login / Signup screen here")

    doc.add_heading("1.2 Booking Local On-Demand Rides (City Ride)", level=2)
    p = doc.add_paragraph(
        "1. Set Pickup Location: Automatically detected via GPS or selected by tapping the interactive map.\n"
        "2. Set Destination: Search by street/landmark or tap destination point on map.\n"
        "3. Choose Vehicle Class:\n"
        "   • Bike / Express: Quick single-passenger transit.\n"
        "   • Rickshaw / Auto: Affordable local group commute.\n"
        "   • Car / AC Ride: Comfortable air-conditioned sedan travel.\n"
        "4. View Upfront Fixed Fare: Guaranteed upfront price before requesting.\n"
        "5. Tap 'Request Ride': Nearby online drivers are alerted.\n"
        "6. Live Map Tracking: View driver's real-time vehicle movement, driver name, photo, vehicle plate, and contact buttons (Call / WhatsApp)."
    )
    add_screenshot_placeholder(doc, "Local Ride Map & Upfront Fare Selection", "Place screenshot of the Map view showing vehicle choices and fare estimate")

    doc.add_heading("1.3 Booking Scheduled City-to-City (Intercity) Rides", level=2)
    p = doc.add_paragraph(
        "1. Open 'City to City' from the home screen quick banner or navigation drawer.\n"
        "2. Choose Route: Select standard routes (e.g., Bannu ➔ Peshawar, Bannu ➔ Islamabad/Rawalpindi, Bannu ➔ D.I. Khan) or enter a custom destination.\n"
        "3. Trip Type: Select One-Way or Round-Trip (specify return date and time).\n"
        "4. Exact Addresses & WhatsApp Location Import:\n"
        "   • Enter precise pickup and drop addresses.\n"
        "   • WhatsApp Map Import: Tap 'WhatsApp Map Link' to paste Google Maps links shared via WhatsApp.\n"
        "5. Price Negotiation (Bargaining):\n"
        "   • Standard Fare: Proceed with system-calculated fare.\n"
        "   • Custom Offer: Enter your desired price in 'Offer Your Price (PKR)'.\n"
        "6. Tap 'Confirm & Book Ride':\n"
        "   • You will receive instant push notifications when Admin accepts your offer, proposes a counter-price, or assigns your driver."
    )
    add_screenshot_placeholder(doc, "City to City Booking & Price Negotiation Box", "Place screenshot of the Intercity booking form with date/time pickers and bargain price box")

    doc.add_heading("1.4 Ride Completion, Payment & Review", level=2)
    p = doc.add_paragraph(
        "1. Cash Payment: Pay the exact confirmed fare to the driver upon dropoff.\n"
        "2. Driver Rating: Rate your driver (1 to 5 stars) and submit comments to help maintain platform safety."
    )
    add_screenshot_placeholder(doc, "Passenger Rating & Review Modal", "Place screenshot of the 5-star rating popup")

    # -------------------------------------------------------------
    # PART 2: DRIVER PARTNER MANUAL
    # -------------------------------------------------------------
    doc.add_page_break()
    h2 = doc.add_heading("Part 2: Driver Partner Manual (Rider)", level=1)
    h2.paragraph_format.space_before = Pt(14)
    h2.paragraph_format.space_after = Pt(8)

    doc.add_heading("2.1 Driver Account Registration & Verification", level=2)
    p = doc.add_paragraph(
        "1. Sign up as 'Driver Partner' in the ShanGo app.\n"
        "2. Enter Vehicle Type (Bike, Car, Rickshaw, HiAce), Vehicle Model, and Registration Number Plate.\n"
        "3. Account Verification: New driver profiles are submitted to the Admin Console for verification.\n"
        "4. Push Alert: You will receive an instant notification '🎉 Driver Account Approved!' once activated."
    )
    add_screenshot_placeholder(doc, "Driver Vehicle Registration Screen", "Place screenshot of the Driver Profile completion form")

    doc.add_heading("2.2 Going Online & Accepting Local Rides", level=2)
    p = doc.add_paragraph(
        "1. Online Status Toggle: Toggle the top switch to 'Online' when you are ready to receive rides.\n"
        "2. Scheduled Rides Toggle: Toggle 'Available for Scheduled Trips' ON/OFF based on your availability for intercity journeys.\n"
        "3. Ride Alert: When a passenger nearby requests a ride, a popup appears with pickup address, dropoff, distance, and total fare.\n"
        "4. Tap 'Accept Ride' ➔ Navigate using Google Maps ➔ Tap 'Arrived' ➔ 'Start Ride' ➔ 'Complete Ride'."
    )
    add_screenshot_placeholder(doc, "Driver Home Screen (Online Switch & Scheduled Toggle)", "Place screenshot of Driver Home screen showing Online toggle and active ride cards")

    doc.add_heading("2.3 Scheduled City-to-City Trips & Transparent Earnings", level=2)
    p = doc.add_paragraph(
        "When Admin assigns you an Intercity scheduled trip, your phone receives a high-priority push notification banner with full financial transparency:\n"
        "• Trip Route: Origin City ➔ Destination City\n"
        "• Departure Date & Time\n"
        "• Total Confirmed Passenger Fare (PKR)\n"
        "• ShanGo Platform Fee (15% Commission)\n"
        "• Net Driver Take-Home Payout (PKR)\n"
        "• Passenger Contact (1-tap Call & WhatsApp direct buttons)\n"
        "• Exact GPS coordinates for pickup and dropoff."
    )
    add_screenshot_placeholder(doc, "Scheduled Trip Details & Net Payout Breakdown", "Place screenshot of the Scheduled Trip card showing 15% commission deduction and net take-home earnings")

    # -------------------------------------------------------------
    # PART 3: ADMIN CONSOLE & OPERATIONS MANUAL
    # -------------------------------------------------------------
    doc.add_page_break()
    h3 = doc.add_heading("Part 3: Admin Console & Operations Manual", level=1)
    h3.paragraph_format.space_before = Pt(14)
    h3.paragraph_format.space_after = Pt(8)

    doc.add_heading("3.1 Admin Authentication & Console Access", level=2)
    p = doc.add_paragraph(
        "Accessing Admin Mode:\n"
        "1. On the Login Screen, tap the Admin Console button (or Shield icon).\n"
        "2. Default Master Credentials:\n"
        "   • Email: shango@gmail.com\n"
        "   • Password: jabiru12\n"
        "3. Authenticated Admin: Any user tagged with isAdmin: true in Firebase can access the console directly."
    )
    add_screenshot_placeholder(doc, "Admin Console Login Modal", "Place screenshot of the Admin passcode entry dialog")

    doc.add_heading("3.2 Admin Capabilities by Console Tabs", level=2)
    
    # Table of Admin Tabs
    admin_table = doc.add_table(rows=7, cols=2)
    admin_table.alignment = WD_TABLE_ALIGNMENT.CENTER
    admin_tab_data = [
        ("Tab Name", "Admin Functions & Control Features"),
        ("1. Dashboard & Revenue", "Live platform revenue counters, total completed rides, online drivers counter, and ShanGo 15% commission revenue calculator."),
        ("2. Riders & Approval", "Review new driver registrations, approve pending drivers, suspend/unsuspend accounts, view passenger reviews, and '👑 Make Admin / Revoke Admin' with 1 tap."),
        ("3. Passengers Desk", "Manage registered passengers, view customer history, suspend accounts, and promote passengers to Admin status."),
        ("4. Account Switches", "Approve or reject Passenger ➔ Driver mode switch applications (with vehicle model and plate inspection)."),
        ("5. Intercity Dispatch", "Complete dispatch hub: review price negotiation offers (Accept / Counter / Reject), assign approved drivers to trips, and cancel bookings with multi-party notifications."),
        ("6. Cities & Pricing", "Create new intercity routes, configure base fares per vehicle category, and adjust distance/duration benchmarks.")
    ]
    for row_idx, row in enumerate(admin_table.rows):
        for col_idx, cell in enumerate(row.cells):
            if row_idx == 0:
                set_cell_background(cell, "1F2937")
                set_cell_margins(cell, 100, 100, 150, 150)
                p = cell.paragraphs[0]
                run = p.add_run(admin_tab_data[row_idx][col_idx])
                run.bold = True
                run.font.color.rgb = RGBColor(0xFF, 0xFF, 0xFF)
                run.font.size = Pt(10)
            else:
                set_cell_background(cell, "F9FAFB" if row_idx % 2 == 0 else "FFFFFF")
                set_cell_margins(cell, 80, 80, 120, 120)
                p = cell.paragraphs[0]
                run = p.add_run(admin_tab_data[row_idx][col_idx])
                run.font.size = Pt(9.5)
                if col_idx == 0:
                    run.bold = True

    doc.add_paragraph().paragraph_format.space_after = Pt(8)
    add_screenshot_placeholder(doc, "Admin Console - Intercity Dispatch & Pricing Tabs", "Place screenshot of the Admin Panel showing the Intercity Dispatch tab and Action buttons")

    doc.add_heading("3.3 Designating & Managing Platform Admins", level=2)
    p = doc.add_paragraph(
        "Promoting Users to Admin:\n"
        "1. In the Admin Panel, go to 'Riders & Approval' or 'Passengers' tab.\n"
        "2. For Drivers: Tap the '👑 Make Admin' button on any driver card.\n"
        "3. For Passengers: Tap the 3-dots (⋮) menu ➔ select 'Promote to Admin'.\n"
        "4. Instant Result: The user receives a '👑 Promoted to Admin!' push notification and gains full Admin Console privileges on their phone."
    )
    add_screenshot_placeholder(doc, "Admin Promotion Confirmation & Admin Badge", "Place screenshot showing the 'Make Admin' confirmation dialog and golden ADMIN badge")

    # -------------------------------------------------------------
    # PART 4: PUSH NOTIFICATION MATRIX & LIMITATIONS
    # -------------------------------------------------------------
    doc.add_page_break()
    h4 = doc.add_heading("Part 4: Master Push Notification Matrix & Limitations", level=1)
    h4.paragraph_format.space_before = Pt(14)
    h4.paragraph_format.space_after = Pt(8)

    notif_table = doc.add_table(rows=10, cols=3)
    notif_table.alignment = WD_TABLE_ALIGNMENT.CENTER
    notif_data = [
        ("Recipient", "Triggering Event", "Push Notification Alert & Content"),
        ("Admin", "Passenger Books Intercity Ride", "🛣️ New Booking: [From] ➔ [To] for PKR [Fare]. Driver assignment needed."),
        ("Admin", "Passenger Proposes Custom Fare", "🏷️ Price Offer: Passenger offered PKR [Fare] for [Route]. Action required."),
        ("Admin", "New Driver Signs Up", "📝 New Driver Registration: [Name] ([Phone]) with [Vehicle]. Verification needed."),
        ("Admin", "Role Switch Requested", "🔄 Switch Request: [Name] ➔ Driver mode. Review in console."),
        ("Driver", "Trip Assigned by Admin", "📅 New Trip: [From] ➔ [To] • Total Fare: PKR [Fare] • 15% Comm: PKR [Fee] • Net Payout: PKR [Net]."),
        ("Driver", "Driver Account Approved", "🎉 Driver Account Approved! You can now go online to receive rides & trips."),
        ("Driver / User", "Promoted to Admin", "👑 Promoted to Admin! You have been granted full Admin Console privileges."),
        ("Passenger", "Driver Confirmed for Trip", "🚖 Trip Confirmed: [From] ➔ [To]. Driver [Name] ([Phone]) assigned. Fare: PKR [Fare]."),
        ("Passenger", "Admin Counters Fare Offer", "🏷️ Price Offer: PKR [CounterFare] for [Route]. Note: '[Admin Message]'.")
    ]
    for row_idx, row in enumerate(notif_table.rows):
        for col_idx, cell in enumerate(row.cells):
            if row_idx == 0:
                set_cell_background(cell, "1F2937")
                set_cell_margins(cell, 100, 100, 120, 120)
                p = cell.paragraphs[0]
                run = p.add_run(notif_data[row_idx][col_idx])
                run.bold = True
                run.font.color.rgb = RGBColor(0xFF, 0xFF, 0xFF)
                run.font.size = Pt(9.5)
            else:
                set_cell_background(cell, "F9FAFB" if row_idx % 2 == 0 else "FFFFFF")
                set_cell_margins(cell, 70, 70, 100, 100)
                p = cell.paragraphs[0]
                run = p.add_run(notif_data[row_idx][col_idx])
                run.font.size = Pt(9)
                if col_idx == 0:
                    run.bold = True

    doc.add_paragraph().paragraph_format.space_after = Pt(12)
    
    doc.add_heading("4.1 System Limitations & Operational Guidelines", level=2)
    p = doc.add_paragraph(
        "1. GPS Precision: GPS accuracy depends on device hardware and mobile network signal. Ensure Location Permission is set to 'Always Allow' or 'While Using App'.\n"
        "2. WhatsApp Map Links: When passengers paste location links from WhatsApp, the app extracts exact latitude and longitude for navigation.\n"
        "3. Network Connectivity: Push notifications require an active Wi-Fi or Cellular Data connection. If a device is offline, messages queue and deliver upon reconnecting.\n"
        "4. Multi-Driver Collision Prevention: Drivers who are already assigned to an ongoing or overlapping scheduled trip are automatically grayed out and disabled in the Admin dispatch dropdown."
    )

    doc.save("d:/client/shango/ShanGo_User_Manual.docx")
    print("ShanGo_User_Manual.docx created successfully!")

if __name__ == '__main__':
    build_manual()
