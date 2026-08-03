import SwiftUI
import WidgetKit

@main
struct KismetWidgetsBundle: WidgetBundle {
	@WidgetBundleBuilder
	var body: some Widget {
		FriendsMapLargeWidget()
		FriendAvailabilityWidget()
		SuggestedMeetupWidget()
		MeetupLiveActivity()
	}
}
