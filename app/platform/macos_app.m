#import <AppKit/AppKit.h>
#import <math.h>
#import "merrow_freeform_canvas.h"

typedef struct {
    uint8_t r;
    uint8_t g;
    uint8_t b;
    uint8_t a;
} MerrowStudioColor;

typedef struct {
    double x;
    double y;
} MerrowStudioPoint;

typedef struct {
    double x;
    double y;
    double width;
    double height;
    double corner_radius;
    MerrowStudioColor fill;
    MerrowStudioColor stroke;
    float stroke_width;
    const char *title;
    double title_x;
    double title_y;
    float title_font_size;
    MerrowStudioColor title_color;
} MerrowStudioSubgraph;

typedef struct {
    uint32_t shape;
    double x;
    double y;
    double width;
    double height;
    MerrowStudioColor fill;
    MerrowStudioColor stroke;
    float stroke_width;
    const char *label;
    MerrowStudioColor label_color;
    float label_font_size;
    double max_text_width;
} MerrowStudioNode;

typedef struct {
    MerrowStudioPoint *points;
    size_t point_count;
    MerrowStudioColor color;
    float thickness;
    uint32_t line_style;
    uint8_t has_arrow;
    uint8_t has_source_arrow;
    MerrowStudioPoint target_from;
    MerrowStudioPoint target_tip;
    MerrowStudioPoint source_from;
    MerrowStudioPoint source_tip;
} MerrowStudioEdge;

typedef struct {
    const char *text;
    double x;
    double y;
    double half_w;
    double half_h;
    float font_size;
    MerrowStudioColor color;
} MerrowStudioEdgeLabel;

typedef struct {
    double width;
    double height;
    MerrowStudioColor background;
    MerrowStudioSubgraph *subgraphs;
    size_t subgraph_count;
    MerrowStudioNode *nodes;
    size_t node_count;
    MerrowStudioEdge *edges;
    size_t edge_count;
    MerrowStudioEdgeLabel *edge_labels;
    size_t edge_label_count;
} MerrowStudioScene;

extern const MerrowStudioScene *merrow_studio_create_default_scene(char *out_source_path, uint32_t out_source_path_len);
extern const MerrowStudioScene *merrow_studio_build_scene(const uint8_t *source_ptr, uint32_t source_len);
extern void merrow_studio_free_scene(const MerrowStudioScene *scene);
extern int merrow_studio_check_mermaid_syntax(const uint8_t *source_ptr, uint32_t source_len, char *out_message, uint32_t out_message_len);
extern int merrow_studio_render_preview_png(const uint8_t *source_ptr, uint32_t source_len, char *out_png_path, uint32_t out_png_path_len, char *out_message, uint32_t out_message_len);
extern int merrow_studio_export_diagram(const uint8_t *source_ptr, uint32_t source_len, const char *output_path_ptr, uint32_t format, double raster_scale, double layout_scale, char *out_message, uint32_t out_message_len);
extern char *merrow_studio_apply_command(const uint8_t *source_ptr, uint32_t source_len, const uint8_t *command_ptr, uint32_t command_len, const uint8_t *context_id_ptr, uint32_t context_id_len, char *out_context_id, uint32_t out_context_id_len, char *out_context_display, uint32_t out_context_display_len, char *out_message, uint32_t out_message_len);
extern char *merrow_studio_shuffle_diagram(const uint8_t *source_ptr, uint32_t source_len, char *out_message, uint32_t out_message_len);
extern const MerrowFreeformGraphSnapshot *merrow_studio_build_editable_graph(const uint8_t *source_ptr, uint32_t source_len, char *out_message, uint32_t out_message_len);
extern void merrow_studio_free_editable_graph(const MerrowFreeformGraphSnapshot *graph);
extern void merrow_studio_free_string(char *text);

static inline NSColor *MerrowNSColor(MerrowStudioColor color) {
    return [NSColor colorWithCalibratedRed:color.r / 255.0
                                     green:color.g / 255.0
                                      blue:color.b / 255.0
                                     alpha:color.a / 255.0];
}

static NSString *MerrowStudioUntitledSource(void) {
    return @"flowchart TD\n    Start([Start])\n    Step[Edit Mermaid here]\n    Start --> Step\n";
}

static void MerrowSetAllowedFileTypes(NSSavePanel *panel, NSArray<NSString *> *extensions) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    panel.allowedFileTypes = extensions;
#pragma clang diagnostic pop
}

static NSBezierPath *MerrowPolygonPath(const CGPoint *points, NSUInteger count) {
    NSBezierPath *path = [NSBezierPath bezierPath];
    if (count == 0) return path;
    [path moveToPoint:points[0]];
    for (NSUInteger idx = 1; idx < count; idx += 1) {
        [path lineToPoint:points[idx]];
    }
    [path closePath];
    return path;
}

static NSBezierPath *MerrowNodePath(const MerrowStudioNode *node) {
    const CGFloat x = (CGFloat)(node->x - node->width / 2.0);
    const CGFloat y = (CGFloat)(node->y - node->height / 2.0);
    const CGFloat w = (CGFloat)node->width;
    const CGFloat h = (CGFloat)node->height;
    const CGFloat cx = (CGFloat)node->x;
    const CGFloat cy = (CGFloat)node->y;
    const CGFloat hw = w / 2.0;
    const CGFloat hh = h / 2.0;

    switch (node->shape) {
        case 0:
            return [NSBezierPath bezierPathWithRect:NSMakeRect(x, y, w, h)];
        case 1:
            return [NSBezierPath bezierPathWithRoundedRect:NSMakeRect(x, y, w, h) xRadius:MIN(MIN(hw, hh), 12.0) yRadius:MIN(MIN(hw, hh), 12.0)];
        case 2: {
            CGPoint points[4] = {
                { cx, cy - hh },
                { cx + hw, cy },
                { cx, cy + hh },
                { cx - hw, cy },
            };
            return MerrowPolygonPath(points, 4);
        }
        case 3:
            return [NSBezierPath bezierPathWithOvalInRect:NSMakeRect(x, y, w, h)];
        case 4: {
            const CGFloat inset = hw * 0.35;
            CGPoint points[6] = {
                { cx - hw + inset, cy - hh },
                { cx + hw - inset, cy - hh },
                { cx + hw, cy },
                { cx + hw - inset, cy + hh },
                { cx - hw + inset, cy + hh },
                { cx - hw, cy },
            };
            return MerrowPolygonPath(points, 6);
        }
        case 5:
        case 6:
            return [NSBezierPath bezierPathWithRoundedRect:NSMakeRect(x, y, w, h) xRadius:hh yRadius:hh];
        case 7: {
            const CGFloat inset = hw * 0.25;
            CGPoint points[4] = {
                { cx - hw + inset, cy - hh },
                { cx + hw - inset, cy - hh },
                { cx + hw, cy + hh },
                { cx - hw, cy + hh },
            };
            return MerrowPolygonPath(points, 4);
        }
        case 8: {
            const CGFloat inset = hw * 0.25;
            CGPoint points[4] = {
                { cx - hw, cy - hh },
                { cx + hw, cy - hh },
                { cx + hw - inset, cy + hh },
                { cx - hw + inset, cy + hh },
            };
            return MerrowPolygonPath(points, 4);
        }
        case 9: {
            const CGFloat slant = hw * 0.25;
            CGPoint points[4] = {
                { cx - hw + slant, cy - hh },
                { cx + hw + slant, cy - hh },
                { cx + hw - slant, cy + hh },
                { cx - hw - slant, cy + hh },
            };
            return MerrowPolygonPath(points, 4);
        }
        case 10: {
            const CGFloat slant = hw * 0.25;
            CGPoint points[4] = {
                { cx - hw - slant, cy - hh },
                { cx + hw - slant, cy - hh },
                { cx + hw + slant, cy + hh },
                { cx - hw + slant, cy + hh },
            };
            return MerrowPolygonPath(points, 4);
        }
        case 11:
            return [NSBezierPath bezierPathWithRect:NSMakeRect(x, y, w, h)];
        default:
            return [NSBezierPath bezierPathWithRect:NSMakeRect(x, y, w, h)];
    }
}

static void MerrowDrawArrow(CGPoint from, CGPoint tip, NSColor *color) {
    const CGFloat dx = tip.x - from.x;
    const CGFloat dy = tip.y - from.y;
    const CGFloat len = hypot(dx, dy);
    if (len < 0.001) return;

    const CGFloat ux = dx / len;
    const CGFloat uy = dy / len;
    const CGFloat px = -uy;
    const CGFloat py = ux;
    const CGFloat size = 10.0;
    const CGFloat halfWidth = size * 0.45;

    CGPoint points[3] = {
        tip,
        { tip.x - ux * size + px * halfWidth, tip.y - uy * size + py * halfWidth },
        { tip.x - ux * size - px * halfWidth, tip.y - uy * size - py * halfWidth },
    };

    [color setFill];
    [MerrowPolygonPath(points, 3) fill];
}

@interface MerrowSceneRenderer : NSObject
@property (nonatomic, assign) const MerrowStudioScene *scene;
@property (nonatomic, strong) NSImage *previewImage;
@property (nonatomic, copy) NSString *previewImagePath;
@property (nonatomic, assign) CGFloat zoom;
@property (nonatomic, assign) CGPoint pan;
@end

@interface MerrowViewportView : NSView
@property (nonatomic, weak) MerrowSceneRenderer *viewportRenderer;
@property (nonatomic, assign) NSPoint lastDragPoint;
@property (nonatomic, assign) BOOL dragging;
@property (nonatomic, strong) NSMagnificationGestureRecognizer *magnifyRecognizer;
@end

@implementation MerrowSceneRenderer

- (void)discardPreviewImage {
    self.previewImage = nil;
    if (self.previewImagePath.length > 0) {
        [[NSFileManager defaultManager] removeItemAtPath:self.previewImagePath error:nil];
        self.previewImagePath = nil;
    }
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _zoom = 1.0;
        _pan = CGPointZero;
    }
    return self;
}

- (void)dealloc {
    if (_scene) {
        merrow_studio_free_scene(_scene);
    }
    [self discardPreviewImage];
}

- (void)replaceScene:(const MerrowStudioScene *)scene {
    if (_scene) {
        merrow_studio_free_scene(_scene);
    }
    _scene = scene;
    [self discardPreviewImage];
}

- (void)replacePreviewImage:(NSImage *)image path:(NSString *)path {
    if (_scene) {
        merrow_studio_free_scene(_scene);
        _scene = NULL;
    }
    [self discardPreviewImage];
    self.previewImage = image;
    self.previewImagePath = [path copy];
}

- (void)resetView {
    self.zoom = 1.0;
    self.pan = CGPointZero;
}

- (void)adjustPanByViewDeltaX:(CGFloat)deltaX deltaY:(CGFloat)deltaY {
    self.pan = CGPointMake(self.pan.x + deltaX, self.pan.y + deltaY);
}

- (void)adjustZoomByFactor:(CGFloat)factor {
    const CGFloat nextZoom = self.zoom * factor;
    self.zoom = fmax(0.25, fmin(nextZoom, 8.0));
}

- (NSDictionary<NSAttributedStringKey, id> *)attributesWithFontSize:(CGFloat)fontSize color:(NSColor *)color {
    NSFont *font = [NSFont fontWithName:@"Lato" size:fontSize];
    if (!font) font = [NSFont systemFontOfSize:fontSize weight:NSFontWeightRegular];
    NSMutableParagraphStyle *style = [[NSMutableParagraphStyle alloc] init];
    style.alignment = NSTextAlignmentCenter;
    style.lineBreakMode = NSLineBreakByWordWrapping;
    return @{ NSFontAttributeName: font, NSForegroundColorAttributeName: color, NSParagraphStyleAttributeName: style };
}

- (NSRect)textRectForNode:(const MerrowStudioNode *)node {
    const CGFloat outerX = (CGFloat)(node->x - node->width / 2.0);
    const CGFloat outerY = (CGFloat)(node->y - node->height / 2.0);
    CGFloat insetX = 10.0;
    CGFloat insetY = 8.0;

    switch (node->shape) {
        case 2:
            insetX = MAX(18.0, node->width * 0.24);
            insetY = MAX(12.0, node->height * 0.20);
            break;
        case 3:
            insetX = MAX(16.0, node->width * 0.18);
            insetY = MAX(12.0, node->height * 0.18);
            break;
        case 4:
            insetX = MAX(18.0, node->width * 0.18);
            insetY = 10.0;
            break;
        case 5:
            insetX = 12.0;
            insetY = MAX(14.0, node->height * 0.22);
            break;
        case 6:
            insetX = MAX(16.0, node->height * 0.28);
            insetY = 8.0;
            break;
        case 7:
        case 8:
        case 9:
        case 10:
            insetX = MAX(16.0, node->width * 0.16);
            insetY = 10.0;
            break;
        case 11:
            insetX = MAX(18.0, node->width * 0.18);
            insetY = 8.0;
            break;
        default:
            break;
    }

    const CGFloat maxWidth = MAX(node->width - insetX * 2.0, 24.0);
    const CGFloat maxHeight = MAX(node->height - insetY * 2.0, 18.0);
    return NSMakeRect(node->x - maxWidth / 2.0, node->y - maxHeight / 2.0, maxWidth, maxHeight);
}

- (void)drawCenteredText:(NSString *)text inRect:(NSRect)rect fontSize:(CGFloat)fontSize color:(NSColor *)color {
    if (text.length == 0) return;

    CGFloat fittedFontSize = fontSize;
    NSDictionary *attrs = nil;
    NSRect measured = NSZeroRect;

    while (fittedFontSize >= 8.0) {
        attrs = [self attributesWithFontSize:fittedFontSize color:color];
        measured = [text boundingRectWithSize:rect.size
                                      options:NSStringDrawingUsesLineFragmentOrigin | NSStringDrawingUsesFontLeading
                                   attributes:attrs];
        if (measured.size.height <= rect.size.height + 0.5) {
            break;
        }
        fittedFontSize -= 0.5;
    }

    NSRect drawRect = rect;
    drawRect.origin.y = rect.origin.y + floor((rect.size.height - measured.size.height) * 0.5);
    drawRect.size.height = MIN(rect.size.height, ceil(measured.size.height));
    [text drawWithRect:drawRect options:NSStringDrawingUsesLineFragmentOrigin | NSStringDrawingUsesFontLeading attributes:attrs];
}

- (void)drawCylinderNode:(const MerrowStudioNode *)node {
    const CGFloat hw = (CGFloat)(node->width / 2.0);
    const CGFloat hh = (CGFloat)(node->height / 2.0);
    const CGFloat x = (CGFloat)(node->x - hw);
    const CGFloat y = (CGFloat)(node->y - hh);
    const CGFloat capH = MIN(MAX(hh * 0.30, 8.0), 14.0);
    NSColor *fillColor = [MerrowNSColor(node->fill) colorUsingColorSpace:[NSColorSpace deviceRGBColorSpace]];
    NSColor *strokeColor = [MerrowNSColor(node->stroke) colorUsingColorSpace:[NSColorSpace deviceRGBColorSpace]];

    NSRect bodyRect = NSMakeRect(x, y + capH, node->width, node->height - capH * 2.0);
    NSRect topOvalRect = NSMakeRect(x, y, node->width, capH * 2.0);
    NSRect bottomOvalRect = NSMakeRect(x, y + node->height - capH * 2.0, node->width, capH * 2.0);

    [fillColor setFill];
    NSRectFill(bodyRect);
    [[NSBezierPath bezierPathWithOvalInRect:bottomOvalRect] fill];
    [[NSBezierPath bezierPathWithOvalInRect:topOvalRect] fill];

    [strokeColor setStroke];
    NSBezierPath *topOval = [NSBezierPath bezierPathWithOvalInRect:topOvalRect];
    topOval.lineWidth = node->stroke_width;
    [topOval stroke];

    NSBezierPath *sides = [NSBezierPath bezierPath];
    [sides moveToPoint:CGPointMake(x, y + capH)];
    [sides lineToPoint:CGPointMake(x, y + node->height - capH)];
    [sides moveToPoint:CGPointMake(x + node->width, y + capH)];
    [sides lineToPoint:CGPointMake(x + node->width, y + node->height - capH)];
    sides.lineWidth = node->stroke_width;
    [sides stroke];

    NSBezierPath *bottomFrontArc = [NSBezierPath bezierPath];
    const CGFloat bottomY = y + node->height - capH;
    const CGFloat leftX = x;
    const CGFloat rightX = x + node->width;
    [bottomFrontArc moveToPoint:CGPointMake(leftX, bottomY)];
    [bottomFrontArc curveToPoint:CGPointMake(rightX, bottomY)
                   controlPoint1:CGPointMake(leftX + node->width * 0.22, bottomY + capH)
                   controlPoint2:CGPointMake(rightX - node->width * 0.22, bottomY + capH)];
    bottomFrontArc.lineWidth = node->stroke_width;
    [bottomFrontArc stroke];
}

- (void)drawNode:(const MerrowStudioNode *)node {
    if (node->shape == 5) {
        [self drawCylinderNode:node];
    } else {
        NSBezierPath *path = MerrowNodePath(node);
        [[MerrowNSColor(node->fill) colorUsingColorSpace:[NSColorSpace deviceRGBColorSpace]] setFill];
        [[MerrowNSColor(node->stroke) colorUsingColorSpace:[NSColorSpace deviceRGBColorSpace]] setStroke];
        path.lineWidth = node->stroke_width;
        [path fill];
        [path stroke];
    }

    if (node->shape == 11) {
        const CGFloat hw = (CGFloat)(node->width / 2.0);
        const CGFloat hh = (CGFloat)(node->height / 2.0);
        const CGFloat inset = MAX(hw * 0.15, 6.0);
        NSBezierPath *left = [NSBezierPath bezierPath];
        [left moveToPoint:CGPointMake(node->x - hw + inset, node->y - hh)];
        [left lineToPoint:CGPointMake(node->x - hw + inset, node->y + hh)];
        left.lineWidth = node->stroke_width;
        [left stroke];
        NSBezierPath *right = [NSBezierPath bezierPath];
        [right moveToPoint:CGPointMake(node->x + hw - inset, node->y - hh)];
        [right lineToPoint:CGPointMake(node->x + hw - inset, node->y + hh)];
        right.lineWidth = node->stroke_width;
        [right stroke];
    }

    if (node->label) {
        NSString *text = [NSString stringWithUTF8String:node->label];
        [self drawCenteredText:text inRect:[self textRectForNode:node] fontSize:node->label_font_size color:MerrowNSColor(node->label_color)];
    }
}

- (void)drawEdge:(const MerrowStudioEdge *)edge {
    if (edge->point_count < 2) return;

    NSBezierPath *path = [NSBezierPath bezierPath];
    [path moveToPoint:CGPointMake(edge->points[0].x, edge->points[0].y)];
    for (size_t idx = 1; idx < edge->point_count; idx += 1) {
        [path lineToPoint:CGPointMake(edge->points[idx].x, edge->points[idx].y)];
    }
    path.lineJoinStyle = NSLineJoinStyleRound;
    path.lineCapStyle = NSLineCapStyleRound;
    path.lineWidth = edge->thickness;

    CGFloat pattern[2] = { 0.0, 0.0 };
    if (edge->line_style == 1) {
        pattern[0] = 10.0;
        pattern[1] = 6.0;
        [path setLineDash:pattern count:2 phase:0.0];
    } else if (edge->line_style == 2) {
        pattern[0] = 4.0;
        pattern[1] = 4.0;
        [path setLineDash:pattern count:2 phase:0.0];
    }

    NSColor *stroke = MerrowNSColor(edge->color);
    [stroke setStroke];
    [path stroke];

    if (edge->has_arrow) {
        MerrowDrawArrow(CGPointMake(edge->target_from.x, edge->target_from.y), CGPointMake(edge->target_tip.x, edge->target_tip.y), stroke);
    }
    if (edge->has_source_arrow) {
        MerrowDrawArrow(CGPointMake(edge->source_from.x, edge->source_from.y), CGPointMake(edge->source_tip.x, edge->source_tip.y), stroke);
    }
}

- (void)drawInView:(NSView *)view {
    const MerrowStudioScene *scene = self.scene;
    NSImage *previewImage = self.previewImage;
    [[NSColor colorWithCalibratedRed:0.93 green:0.94 blue:0.96 alpha:1.0] setFill];
    NSRectFill(view.bounds);

    if (!scene && !previewImage) return;

    const CGFloat contentWidth = scene ? scene->width : previewImage.size.width;
    const CGFloat contentHeight = scene ? scene->height : previewImage.size.height;

    const CGFloat availableWidth = MAX(view.bounds.size.width - 48.0, 64.0);
    const CGFloat availableHeight = MAX(view.bounds.size.height - 48.0, 64.0);
    const CGFloat fitScaleX = contentWidth > 0.0 ? availableWidth / contentWidth : 1.0;
    const CGFloat fitScaleY = contentHeight > 0.0 ? availableHeight / contentHeight : 1.0;
    const CGFloat fitScale = MAX(MIN(fitScaleX, fitScaleY), 0.01);
    const CGFloat totalScale = fitScale * self.zoom;

    [NSGraphicsContext saveGraphicsState];
    NSAffineTransform *transform = [NSAffineTransform transform];
    [transform translateXBy:view.bounds.size.width / 2.0 + self.pan.x yBy:view.bounds.size.height / 2.0 + self.pan.y];
    [transform scaleBy:totalScale];
    [transform translateXBy:-contentWidth / 2.0 yBy:-contentHeight / 2.0];
    [transform concat];

    if (!scene && previewImage) {
        [previewImage drawInRect:NSMakeRect(0.0, 0.0, contentWidth, contentHeight)
                        fromRect:NSZeroRect
                       operation:NSCompositingOperationSourceOver
                        fraction:1.0
                  respectFlipped:YES
                           hints:@{ NSImageHintInterpolation : @(NSImageInterpolationHigh) }];
        [NSGraphicsContext restoreGraphicsState];
        return;
    }

    [[MerrowNSColor(scene->background) colorUsingColorSpace:[NSColorSpace deviceRGBColorSpace]] setFill];
    NSRectFill(NSMakeRect(0.0, 0.0, scene->width, scene->height));

    for (size_t idx = 0; idx < scene->subgraph_count; idx += 1) {
        const MerrowStudioSubgraph *subgraph = &scene->subgraphs[idx];
        NSBezierPath *path = [NSBezierPath bezierPathWithRoundedRect:NSMakeRect(subgraph->x, subgraph->y, subgraph->width, subgraph->height) xRadius:subgraph->corner_radius yRadius:subgraph->corner_radius];
        path.lineWidth = subgraph->stroke_width;
        [MerrowNSColor(subgraph->fill) setFill];
        [MerrowNSColor(subgraph->stroke) setStroke];
        [path fill];
        [path stroke];

        if (subgraph->title) {
            NSString *title = [NSString stringWithUTF8String:subgraph->title];
            NSDictionary *attrs = @{ NSFontAttributeName: [NSFont systemFontOfSize:subgraph->title_font_size weight:NSFontWeightSemibold], NSForegroundColorAttributeName: MerrowNSColor(subgraph->title_color) };
            [title drawAtPoint:CGPointMake(subgraph->title_x, subgraph->title_y) withAttributes:attrs];
        }
    }

    for (size_t idx = 0; idx < scene->edge_count; idx += 1) {
        [self drawEdge:&scene->edges[idx]];
    }

    for (size_t idx = 0; idx < scene->node_count; idx += 1) {
        [self drawNode:&scene->nodes[idx]];
    }

    for (size_t idx = 0; idx < scene->edge_label_count; idx += 1) {
        const MerrowStudioEdgeLabel *label = &scene->edge_labels[idx];
        NSRect labelRect = NSMakeRect(label->x - label->half_w, label->y - label->half_h, label->half_w * 2.0, label->half_h * 2.0);
        [[NSColor colorWithCalibratedWhite:1.0 alpha:0.92] setFill];
        [[NSBezierPath bezierPathWithRoundedRect:labelRect xRadius:4.0 yRadius:4.0] fill];
        if (label->text) {
            NSString *text = [NSString stringWithUTF8String:label->text];
            [self drawCenteredText:text inRect:labelRect fontSize:label->font_size color:MerrowNSColor(label->color)];
        }
    }

    [NSGraphicsContext restoreGraphicsState];
}

@end

@implementation MerrowViewportView

- (instancetype)initWithFrame:(NSRect)frameRect {
    self = [super initWithFrame:frameRect];
    if (self) {
        self.wantsLayer = YES;
        self.layer.backgroundColor = [NSColor colorWithCalibratedRed:0.93 green:0.94 blue:0.96 alpha:1.0].CGColor;
        _magnifyRecognizer = [[NSMagnificationGestureRecognizer alloc] initWithTarget:self action:@selector(handleMagnifyGesture:)];
        [self addGestureRecognizer:_magnifyRecognizer];
    }
    return self;
}

- (BOOL)isFlipped {
    return YES;
}

- (BOOL)acceptsFirstResponder {
    return YES;
}

- (void)drawRect:(NSRect)dirtyRect {
    (void)dirtyRect;
    [self.viewportRenderer drawInView:self];
}

- (void)mouseDown:(NSEvent *)event {
    self.dragging = YES;
    self.lastDragPoint = [self convertPoint:event.locationInWindow fromView:nil];
}

- (void)mouseDragged:(NSEvent *)event {
    if (!self.dragging || !self.viewportRenderer) return;
    NSPoint point = [self convertPoint:event.locationInWindow fromView:nil];
    CGFloat dx = point.x - self.lastDragPoint.x;
    CGFloat dy = point.y - self.lastDragPoint.y;
    [self.viewportRenderer adjustPanByViewDeltaX:dx deltaY:dy];
    self.lastDragPoint = point;
    [self setNeedsDisplay:YES];
}

- (void)mouseUp:(NSEvent *)event {
    (void)event;
    self.dragging = NO;
}

- (void)scrollWheel:(NSEvent *)event {
    if (!self.viewportRenderer) {
        [super scrollWheel:event];
        return;
    }

    if (fabs(event.scrollingDeltaY) >= fabs(event.scrollingDeltaX)) {
        const CGFloat factor = pow(1.01, -event.scrollingDeltaY);
        [self.viewportRenderer adjustZoomByFactor:factor];
    } else {
        [self.viewportRenderer adjustPanByViewDeltaX:-event.scrollingDeltaX deltaY:event.scrollingDeltaY];
    }
    [self setNeedsDisplay:YES];
}

- (void)magnifyWithEvent:(NSEvent *)event {
    if (!self.viewportRenderer) return;
    [self.viewportRenderer adjustZoomByFactor:(1.0 + event.magnification)];
    [self setNeedsDisplay:YES];
}

- (void)handleMagnifyGesture:(NSMagnificationGestureRecognizer *)recognizer {
    if (!self.viewportRenderer) return;
    if (recognizer.state == NSGestureRecognizerStateBegan || recognizer.state == NSGestureRecognizerStateChanged) {
        [self.viewportRenderer adjustZoomByFactor:(1.0 + recognizer.magnification)];
        recognizer.magnification = 0.0;
        [self setNeedsDisplay:YES];
    }
}

- (void)smartMagnifyWithEvent:(NSEvent *)event {
    (void)event;
    if (!self.viewportRenderer) return;
    [self.viewportRenderer resetView];
    [self setNeedsDisplay:YES];
}

@end

@interface MerrowEditorTextView : NSTextView
@end

@implementation MerrowEditorTextView

- (BOOL)acceptsFirstMouse:(NSEvent *)event {
    (void)event;
    return YES;
}

- (void)scrollWheel:(NSEvent *)event {
    NSScrollView *scrollView = self.enclosingScrollView;
    if (scrollView) {
        [scrollView scrollWheel:event];
        return;
    }
    [super scrollWheel:event];
}

@end

typedef NS_ENUM(NSInteger, MerrowFreeformInspectorMode) {
    MerrowFreeformInspectorModeCanvas = 0,
    MerrowFreeformInspectorModeAddObject = 1,
    MerrowFreeformInspectorModeAddLink = 2,
    MerrowFreeformInspectorModeNode = 3,
    MerrowFreeformInspectorModeGroup = 4,
    MerrowFreeformInspectorModeEdge = 5,
};

@interface MerrowStudioAppDelegate : NSObject <NSApplicationDelegate, NSSplitViewDelegate, NSWindowDelegate, NSTextViewDelegate, MerrowFreeformCanvasComponentDelegate>
@property (nonatomic, strong) NSWindow *window;
@property (nonatomic, strong) NSSplitView *splitView;
@property (nonatomic, strong) NSTextField *statusLabel;
@property (nonatomic, strong) NSTextField *contextLabel;
@property (nonatomic, strong) NSTextField *commandField;
@property (nonatomic, strong) NSButton *commandButton;
@property (nonatomic, strong) MerrowSceneRenderer *viewerRenderer;
@property (nonatomic, strong) MerrowViewportView *viewerView;
@property (nonatomic, strong) NSView *viewerPane;
@property (nonatomic, strong) NSView *viewerPaneContentHost;
@property (nonatomic, strong) NSView *editorPane;
@property (nonatomic, strong) NSView *editorPaneContentHost;
@property (nonatomic, strong) NSScrollView *editorScrollView;
@property (nonatomic, strong) NSScrollView *freeformToolsScrollView;
@property (nonatomic, strong) MerrowFreeformCanvasComponent *freeformCanvasComponent;
@property (nonatomic, strong) NSTextView *editorTextView;
@property (nonatomic, strong) NSTextField *viewerPaneTitleLabel;
@property (nonatomic, strong) NSTextField *viewerPaneSubtitleLabel;
@property (nonatomic, strong) NSTextField *editorPaneTitleLabel;
@property (nonatomic, strong) NSTextField *editorPaneSubtitleLabel;
@property (nonatomic, strong) NSTextField *freeformSelectionLabel;
@property (nonatomic, strong) NSTextField *freeformCreateStatusLabel;
@property (nonatomic, strong) NSTextField *freeformInspectorIntroLabel;
@property (nonatomic, strong) NSTextField *freeformInspectorIntroDetailLabel;
@property (nonatomic, strong) NSStackView *freeformCanvasModeSection;
@property (nonatomic, strong) NSStackView *freeformAddObjectModeSection;
@property (nonatomic, strong) NSStackView *freeformAddLinkModeSection;
@property (nonatomic, strong) NSStackView *freeformDefaultsModeSection;
@property (nonatomic, strong) NSStackView *freeformSelectionModeSection;
@property (nonatomic, strong) NSStackView *freeformObjectModeSection;
@property (nonatomic, strong) NSStackView *freeformEdgeModeSection;
@property (nonatomic, strong) NSStackView *freeformShapePickerSection;
@property (nonatomic, strong) NSTextField *freeformObjectLabelCaption;
@property (nonatomic, strong) NSTextField *freeformObjectSizeCaption;
@property (nonatomic, strong) NSColorWell *freeformCanvasBackgroundColorWell;
@property (nonatomic, strong) NSSlider *freeformCanvasBackgroundOpacitySlider;
@property (nonatomic, strong) NSTextField *freeformCanvasBackgroundOpacityValueLabel;
@property (nonatomic, strong) NSColorWell *freeformDefaultNodeFillColorWell;
@property (nonatomic, strong) NSColorWell *freeformDefaultNodeStrokeColorWell;
@property (nonatomic, strong) NSSlider *freeformDefaultNodeStrokeWidthSlider;
@property (nonatomic, strong) NSTextField *freeformDefaultNodeStrokeWidthValueLabel;
@property (nonatomic, strong) NSColorWell *freeformDefaultSubgraphFillColorWell;
@property (nonatomic, strong) NSColorWell *freeformDefaultSubgraphStrokeColorWell;
@property (nonatomic, strong) NSSlider *freeformDefaultSubgraphStrokeWidthSlider;
@property (nonatomic, strong) NSTextField *freeformDefaultSubgraphStrokeWidthValueLabel;
@property (nonatomic, strong) NSColorWell *freeformDefaultEdgeColorWell;
@property (nonatomic, strong) NSSlider *freeformDefaultEdgeThicknessSlider;
@property (nonatomic, strong) NSTextField *freeformDefaultEdgeThicknessValueLabel;
@property (nonatomic, strong) NSPopUpButton *freeformDefaultEdgePatternPopup;
@property (nonatomic, strong) NSPopUpButton *freeformDefaultEdgeArrowPopup;
@property (nonatomic, strong) NSTextField *freeformNodeLabelField;
@property (nonatomic, strong) NSTextField *freeformWidthField;
@property (nonatomic, strong) NSTextField *freeformHeightField;
@property (nonatomic, strong) NSPopUpButton *freeformShapePopup;
@property (nonatomic, strong) NSButton *freeformAddShapeButton;
@property (nonatomic, strong) NSButton *freeformAddGroupButton;
@property (nonatomic, strong) NSButton *freeformCancelCreateButton;
@property (nonatomic, strong) NSColorWell *freeformFillColorWell;
@property (nonatomic, strong) NSColorWell *freeformStrokeColorWell;
@property (nonatomic, strong) NSSlider *freeformStrokeWidthSlider;
@property (nonatomic, strong) NSTextField *freeformStrokeWidthValueLabel;
@property (nonatomic, strong) NSTextField *freeformEdgeLabelField;
@property (nonatomic, strong) NSColorWell *freeformEdgeColorWell;
@property (nonatomic, strong) NSSlider *freeformEdgeThicknessSlider;
@property (nonatomic, strong) NSTextField *freeformEdgeThicknessValueLabel;
@property (nonatomic, strong) NSPopUpButton *freeformEdgePatternPopup;
@property (nonatomic, strong) NSPopUpButton *freeformEdgeArrowPopup;
@property (nonatomic, strong) NSPopUpButton *freeformConnectorSourcePopup;
@property (nonatomic, strong) NSPopUpButton *freeformConnectorTargetPopup;
@property (nonatomic, strong) NSButton *freeformAddConnectorButton;
@property (nonatomic, strong) NSMenuItem *mermaidModeMenuItem;
@property (nonatomic, strong) NSMenuItem *freeformModeMenuItem;
@property (nonatomic, strong) NSMenuItem *freeformInsertGroupMenuItem;
@property (nonatomic, strong) NSMenu *freeformInsertShapeMenu;
@property (nonatomic, strong) NSMenuItem *insertAddObjectMenuItem;
@property (nonatomic, strong) NSMenuItem *insertAddLinkMenuItem;
@property (nonatomic, copy) NSString *currentSourcePath;
@property (nonatomic, assign) BOOL currentDocumentIsFreeform;
@property (nonatomic, assign) BOOL isApplyingHighlighting;
@property (nonatomic, assign) BOOL isSynchronizingEditor;
@property (nonatomic, assign) BOOL freeformModeEnabled;
@property (nonatomic, assign) NSUInteger editorGeneration;
@property (nonatomic, assign) MerrowFreeformInspectorMode freeformInspectorMode;
@property (nonatomic, assign) BOOL freeformInspectorModeOverrideActive;
@property (nonatomic, strong) dispatch_queue_t editorWorkQueue;
@property (nonatomic, copy) NSString *currentCommandContextId;
@property (nonatomic, copy) NSString *currentCommandContextDisplay;
@end

@implementation MerrowStudioAppDelegate

- (NSAppearance *)darkInspectorAppearance {
    return [NSAppearance appearanceNamed:NSAppearanceNameDarkAqua];
}

- (NSString *)appDisplayName {
    NSString *name = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleName"];
    return name.length > 0 ? name : @"Merrow Studio";
}

- (void)showAboutDialog:(id)sender {
    (void)sender;

    NSBundle *bundle = [NSBundle mainBundle];
    NSString *appName = [self appDisplayName];
    NSString *shortVersion = [bundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"] ?: @"";
    NSString *buildVersion = [bundle objectForInfoDictionaryKey:@"CFBundleVersion"] ?: @"";
    NSImage *appIcon = NSApp.applicationIconImage ?: [NSImage imageNamed:@"NSApplicationIcon"];

    NSMutableDictionary<NSAboutPanelOptionKey, id> *options = [NSMutableDictionary dictionaryWithObject:appName
                                                                                                   forKey:@"ApplicationName"];
    if (shortVersion.length > 0) {
        options[@"ApplicationVersion"] = shortVersion;
    }
    if (buildVersion.length > 0 && ![buildVersion isEqualToString:shortVersion]) {
        options[@"Version"] = [NSString stringWithFormat:@"Build %@", buildVersion];
    }
    if (appIcon) {
        options[@"ApplicationIcon"] = appIcon;
    }

    [NSApp orderFrontStandardAboutPanelWithOptions:options];
    [NSApp activateIgnoringOtherApps:YES];
}

- (void)styleDarkInspectorButton:(NSButton *)button {
    if (!button || [button isKindOfClass:[NSColorWell class]]) return;

    button.appearance = [self darkInspectorAppearance];
    button.bordered = YES;
    button.bezelStyle = NSBezelStyleRounded;

    if (@available(macOS 10.14, *)) {
        button.bezelColor = [NSColor colorWithRed:0.23 green:0.27 blue:0.33 alpha:1.0];
        button.contentTintColor = [NSColor colorWithRed:0.95 green:0.96 blue:0.98 alpha:1.0];
    }
}

- (void)applyDarkInspectorControlThemeToView:(NSView *)view {
    if (!view) return;

    if ([view isKindOfClass:[NSButton class]]) {
        [self styleDarkInspectorButton:(NSButton *)view];
    }

    for (NSView *subview in view.subviews) {
        [self applyDarkInspectorControlThemeToView:subview];
    }
}

- (BOOL)validateMenuItem:(NSMenuItem *)menuItem {
    SEL action = menuItem.action;
    if (action == @selector(resetFreeformToMermaid:)) {
        return self.freeformModeEnabled || self.currentDocumentIsFreeform;
    }
    if (action == @selector(beginFreeformAddGroup:) ||
        action == @selector(beginFreeformAddShapeFromMenu:) ||
        action == @selector(showFreeformAddObjectMode:) ||
        action == @selector(showFreeformAddLinkMode:)) {
        return self.freeformModeEnabled;
    }
    return YES;
}

- (NSColor *)editorColorForWord:(NSString *)word {
    static NSSet<NSString *> *keywords;
    static NSSet<NSString *> *directions;
    if (keywords == nil || directions == nil) {
        keywords = [NSSet setWithArray:@[@"graph", @"flowchart", @"subgraph", @"end", @"classDef", @"class", @"style", @"click", @"linkStyle"]];
        directions = [NSSet setWithArray:@[@"TD", @"TB", @"LR", @"RL", @"BT"]];
    }

    if ([keywords containsObject:word]) {
        return [NSColor colorWithRed:0.98 green:0.67 blue:0.33 alpha:1.0];
    }
    if ([directions containsObject:word]) {
        return [NSColor colorWithRed:0.45 green:0.78 blue:0.98 alpha:1.0];
    }
    return [NSColor colorWithRed:0.86 green:0.88 blue:0.91 alpha:1.0];
}

- (NSArray<NSDictionary *> *)segmentsForLine:(NSString *)line {
    NSMutableArray<NSDictionary *> *segments = [NSMutableArray array];
    if (line.length == 0) {
        return segments;
    }

    if ([line hasPrefix:@"%%"]) {
        [segments addObject:@{ @"text": line, @"color": [NSColor colorWithRed:0.48 green:0.66 blue:0.52 alpha:1.0] }];
        return segments;
    }

    NSArray<NSString *> *arrows = @[ @"<==>", @"<-.->", @"<-->", @"==>", @"-.->", @"-->", @"---", @"<:::", @":::" ];
    NSCharacterSet *wordSet = [NSCharacterSet characterSetWithCharactersInString:@"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_"];

    NSUInteger idx = 0;
    while (idx < line.length) {
        NSString *remaining = [line substringFromIndex:idx];
        BOOL matchedArrow = NO;
        for (NSString *arrow in arrows) {
            if ([remaining hasPrefix:arrow]) {
                [segments addObject:@{ @"text": arrow, @"color": [NSColor colorWithRed:0.96 green:0.43 blue:0.43 alpha:1.0] }];
                idx += arrow.length;
                matchedArrow = YES;
                break;
            }
        }
        if (matchedArrow) continue;

        unichar c = [line characterAtIndex:idx];
        if (c == '"') {
            NSUInteger start = idx;
            idx += 1;
            while (idx < line.length) {
                unichar q = [line characterAtIndex:idx];
                idx += 1;
                if (q == '"') break;
            }
            NSString *chunk = [line substringWithRange:NSMakeRange(start, idx - start)];
            [segments addObject:@{ @"text": chunk, @"color": [NSColor colorWithRed:0.62 green:0.83 blue:0.57 alpha:1.0] }];
            continue;
        }

        if ([[NSCharacterSet whitespaceCharacterSet] characterIsMember:c]) {
            NSUInteger start = idx;
            while (idx < line.length && [[NSCharacterSet whitespaceCharacterSet] characterIsMember:[line characterAtIndex:idx]]) {
                idx += 1;
            }
            [segments addObject:@{ @"text": [line substringWithRange:NSMakeRange(start, idx - start)], @"color": [NSColor clearColor] }];
            continue;
        }

        if ([wordSet characterIsMember:c]) {
            NSUInteger start = idx;
            while (idx < line.length && [wordSet characterIsMember:[line characterAtIndex:idx]]) {
                idx += 1;
            }
            NSString *word = [line substringWithRange:NSMakeRange(start, idx - start)];
            [segments addObject:@{ @"text": word, @"color": [self editorColorForWord:word] }];
            continue;
        }

        NSString *chunk = [line substringWithRange:NSMakeRange(idx, 1)];
        [segments addObject:@{ @"text": chunk, @"color": [NSColor colorWithRed:0.73 green:0.75 blue:0.80 alpha:1.0] }];
        idx += 1;
    }

    return segments;
}

- (NSDictionary<NSAttributedStringKey, id> *)baseEditorAttributes {
    NSFont *font = [NSFont fontWithName:@"Menlo-Regular" size:14.0];
    if (!font) {
        font = [NSFont monospacedSystemFontOfSize:14.0 weight:NSFontWeightRegular];
    }
    NSMutableParagraphStyle *style = [[NSMutableParagraphStyle alloc] init];
    style.lineHeightMultiple = 1.14;
    return @{
        NSFontAttributeName: font,
        NSForegroundColorAttributeName: [NSColor colorWithRed:0.86 green:0.88 blue:0.91 alpha:1.0],
        NSParagraphStyleAttributeName: style,
    };
}

- (void)applySyntaxHighlighting {
    if (!self.editorTextView) return;

    NSTextStorage *storage = self.editorTextView.textStorage;
    NSString *source = self.editorTextView.string ?: @"";
    if (storage.length == 0) {
        self.editorTextView.typingAttributes = [self baseEditorAttributes];
        return;
    }

    NSDictionary<NSAttributedStringKey, id> *baseAttrs = [self baseEditorAttributes];
    NSRange fullRange = NSMakeRange(0, storage.length);

    self.isApplyingHighlighting = YES;
    [storage beginEditing];
    [storage setAttributes:baseAttrs range:fullRange];

    [source enumerateSubstringsInRange:NSMakeRange(0, source.length)
                               options:NSStringEnumerationByLines
                            usingBlock:^(NSString *line, NSRange lineRange, NSRange enclosingRange, BOOL *stop) {
        (void)enclosingRange;
        (void)stop;

        if (line.length == 0) return;

        if ([line hasPrefix:@"%%"]) {
            [storage addAttribute:NSForegroundColorAttributeName
                            value:[NSColor colorWithRed:0.48 green:0.66 blue:0.52 alpha:1.0]
                            range:lineRange];
            return;
        }

        NSArray<NSString *> *arrows = @[ @"<==>", @"<-.->", @"<-->", @"==>", @"-.->", @"-->", @"---", @"<:::", @":::" ];
        NSCharacterSet *wordSet = [NSCharacterSet characterSetWithCharactersInString:@"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_"];

        NSUInteger idx = 0;
        while (idx < line.length) {
            NSString *remaining = [line substringFromIndex:idx];
            BOOL matchedArrow = NO;
            for (NSString *arrow in arrows) {
                if ([remaining hasPrefix:arrow]) {
                    [storage addAttribute:NSForegroundColorAttributeName
                                    value:[NSColor colorWithRed:0.96 green:0.43 blue:0.43 alpha:1.0]
                                    range:NSMakeRange(lineRange.location + idx, arrow.length)];
                    idx += arrow.length;
                    matchedArrow = YES;
                    break;
                }
            }
            if (matchedArrow) continue;

            unichar c = [line characterAtIndex:idx];
            if (c == '"') {
                NSUInteger start = idx;
                idx += 1;
                while (idx < line.length) {
                    unichar q = [line characterAtIndex:idx];
                    idx += 1;
                    if (q == '"') break;
                }
                [storage addAttribute:NSForegroundColorAttributeName
                                value:[NSColor colorWithRed:0.62 green:0.83 blue:0.57 alpha:1.0]
                                range:NSMakeRange(lineRange.location + start, idx - start)];
                continue;
            }

            if ([wordSet characterIsMember:c]) {
                NSUInteger start = idx;
                while (idx < line.length && [wordSet characterIsMember:[line characterAtIndex:idx]]) {
                    idx += 1;
                }
                NSString *word = [line substringWithRange:NSMakeRange(start, idx - start)];
                NSColor *color = [self editorColorForWord:word];
                [storage addAttribute:NSForegroundColorAttributeName
                                value:color
                                range:NSMakeRange(lineRange.location + start, idx - start)];
                continue;
            }

            idx += 1;
        }
    }];

    [storage endEditing];
    self.isApplyingHighlighting = NO;
    self.editorTextView.typingAttributes = baseAttrs;
}

- (void)debounceSyntaxHighlighting {
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(applySyntaxHighlightingIfCurrent) object:nil];
    [self performSelector:@selector(applySyntaxHighlightingIfCurrent) withObject:nil afterDelay:0.06];
}

- (void)applySyntaxHighlightingIfCurrent {
    if (self.isApplyingHighlighting) return;
    [self applySyntaxHighlighting];
}

- (void)requestEditorAnalysis {
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(processEditorChange) object:nil];
    [self performSelector:@selector(processEditorChange) withObject:nil afterDelay:0.45];
}

- (void)clearCommandContext {
    self.currentCommandContextId = nil;
    self.currentCommandContextDisplay = nil;
    self.contextLabel.stringValue = @"it=-";
}

- (void)updateCommandContextId:(NSString *)contextId display:(NSString *)displayText {
    NSString *trimmedId = [contextId stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] ?: @"";
    NSString *trimmedDisplay = [displayText stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] ?: @"";
    if (trimmedId.length == 0) {
        [self clearCommandContext];
        return;
    }

    self.currentCommandContextId = [trimmedId copy];
    self.currentCommandContextDisplay = trimmedDisplay.length > 0 ? [trimmedDisplay copy] : [trimmedId copy];
    self.contextLabel.stringValue = [NSString stringWithFormat:@"it=%@", self.currentCommandContextDisplay ?: self.currentCommandContextId];
}

- (void)replaceEditorSourceFromCommand:(NSString *)source status:(NSString *)statusMessage contextId:(NSString *)contextId contextDisplay:(NSString *)contextDisplay {
    if (!self.editorTextView) return;

    self.isSynchronizingEditor = YES;
    NSRange previousSelection = self.editorTextView.selectedRange;
    [self.editorTextView setString:source ?: @""];
    [self applySyntaxHighlighting];
    self.editorGeneration += 1;
    [self markDocumentEdited:YES];
    [self requestEditorAnalysis];

    NSUInteger maxLocation = self.editorTextView.string.length;
    NSUInteger clampedLocation = MIN(previousSelection.location, maxLocation);
    NSUInteger clampedLength = MIN(previousSelection.length, maxLocation - clampedLocation);
    [self.editorTextView setSelectedRange:NSMakeRange(clampedLocation, clampedLength)];
    [self.editorTextView scrollRangeToVisible:NSMakeRange(clampedLocation, clampedLength)];
    self.isSynchronizingEditor = NO;

    [self updateCommandContextId:contextId display:contextDisplay];
    self.statusLabel.stringValue = statusMessage ?: @"Command applied.";
}

- (NSTextField *)freeformPanelLabel:(NSString *)text size:(CGFloat)size weight:(NSFontWeight)weight color:(NSColor *)color {
    NSTextField *label = [NSTextField labelWithString:text ?: @""];
    label.translatesAutoresizingMaskIntoConstraints = NO;
    label.font = [NSFont systemFontOfSize:size weight:weight];
    label.textColor = color;
    label.lineBreakMode = NSLineBreakByWordWrapping;
    label.maximumNumberOfLines = 0;
    return label;
}

- (NSView *)freeformSectionViewWithTitle:(NSString *)title lines:(NSArray<NSString *> *)lines {
    NSStackView *section = [[NSStackView alloc] initWithFrame:NSZeroRect];
    section.translatesAutoresizingMaskIntoConstraints = NO;
    section.orientation = NSUserInterfaceLayoutOrientationVertical;
    section.alignment = NSLayoutAttributeLeading;
    section.spacing = 6.0;

    [section addArrangedSubview:[self freeformPanelLabel:title
                                                    size:11.0
                                                  weight:NSFontWeightSemibold
                                                   color:[NSColor colorWithRed:0.55 green:0.60 blue:0.68 alpha:1.0]]];

    for (NSString *line in lines) {
        [section addArrangedSubview:[self freeformPanelLabel:line
                                                        size:12.0
                                                      weight:NSFontWeightRegular
                                                       color:[NSColor colorWithRed:0.87 green:0.89 blue:0.93 alpha:1.0]]];
    }

    return section;
}

- (NSString *)selectedObjectIdForPopup:(NSPopUpButton *)popup {
    id representedObject = popup.selectedItem.representedObject;
    return [representedObject isKindOfClass:[NSString class]] ? representedObject : nil;
}

- (void)populateFreeformConnectorPopup:(NSPopUpButton *)popup
                           withObjects:(NSArray<NSDictionary *> *)objects
                       preferredObject:(NSString *)preferredObjectId {
    [popup removeAllItems];
    for (NSDictionary *object in objects) {
        NSString *title = [object[@"title"] isKindOfClass:[NSString class]] ? object[@"title"] : @"Untitled";
        NSString *objectId = [object[@"id"] isKindOfClass:[NSString class]] ? object[@"id"] : nil;
        if (objectId.length == 0) continue;
        NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:title action:nil keyEquivalent:@""];
        item.representedObject = objectId;
        [popup.menu addItem:item];
    }

    if (popup.numberOfItems == 0) {
        [popup addItemWithTitle:@"Need at least two shapes or groups"];
        popup.enabled = NO;
        return;
    }

    popup.enabled = YES;
    if (preferredObjectId.length > 0) {
        for (NSMenuItem *item in popup.itemArray) {
            if ([item.representedObject isKindOfClass:[NSString class]] && [item.representedObject isEqualToString:preferredObjectId]) {
                [popup selectItem:item];
                return;
            }
        }
    }
    [popup selectItemAtIndex:0];
}

- (NSArray<NSDictionary *> *)freeformShapeOptionsForGraphType:(MerrowFreeformGraphType)graphType {
    switch (graphType) {
        case MerrowFreeformGraphTypeSequence:
            return @[
                @{ @"title": @"Rounded Rectangle", @"shape": @1 },
                @{ @"title": @"Rectangle", @"shape": @0 },
                @{ @"title": @"Circle", @"shape": @3 },
                @{ @"title": @"Stadium", @"shape": @6 },
            ];
        case MerrowFreeformGraphTypeClass:
            return @[
                @{ @"title": @"Rectangle", @"shape": @0 },
                @{ @"title": @"Rounded Rectangle", @"shape": @1 },
                @{ @"title": @"Circle", @"shape": @3 },
                @{ @"title": @"Hexagon", @"shape": @4 },
            ];
        case MerrowFreeformGraphTypeER:
            return @[
                @{ @"title": @"Rectangle", @"shape": @0 },
                @{ @"title": @"Rounded Rectangle", @"shape": @1 },
                @{ @"title": @"Diamond", @"shape": @2 },
                @{ @"title": @"Circle", @"shape": @3 },
            ];
        case MerrowFreeformGraphTypeFlowchart:
        default:
            return @[
                @{ @"title": @"Rounded Rectangle", @"shape": @1 },
                @{ @"title": @"Rectangle", @"shape": @0 },
                @{ @"title": @"Diamond", @"shape": @2 },
                @{ @"title": @"Circle", @"shape": @3 },
                @{ @"title": @"Hexagon", @"shape": @4 },
                @{ @"title": @"Cylinder", @"shape": @5 },
                @{ @"title": @"Stadium", @"shape": @6 },
                @{ @"title": @"Subroutine", @"shape": @11 },
            ];
    }
}

- (void)rebuildFreeformShapePopupOptions {
    NSNumber *selectedShape = [self.freeformShapePopup.selectedItem.representedObject isKindOfClass:[NSNumber class]] ? self.freeformShapePopup.selectedItem.representedObject : nil;
    NSArray<NSDictionary *> *options = [self freeformShapeOptionsForGraphType:self.freeformCanvasComponent.graphType];
    [self.freeformShapePopup removeAllItems];
    for (NSDictionary *option in options) {
        NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:option[@"title"] action:nil keyEquivalent:@""];
        item.representedObject = option[@"shape"];
        [self.freeformShapePopup.menu addItem:item];
    }

    NSMenuItem *itemToSelect = nil;
    for (NSMenuItem *item in self.freeformShapePopup.itemArray) {
        if (selectedShape && [item.representedObject isKindOfClass:[NSNumber class]] && [item.representedObject isEqualToNumber:selectedShape]) {
            itemToSelect = item;
            break;
        }
    }
    [self.freeformShapePopup selectItem:itemToSelect ?: self.freeformShapePopup.itemArray.firstObject];
}

- (void)rebuildFreeformInsertMenu {
    if (!self.freeformInsertShapeMenu) return;

    [self.freeformInsertShapeMenu removeAllItems];
    NSArray<NSDictionary *> *options = [self freeformShapeOptionsForGraphType:self.freeformCanvasComponent.graphType];
    for (NSDictionary *option in options) {
        NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:option[@"title"] action:@selector(beginFreeformAddShapeFromMenu:) keyEquivalent:@""];
        item.target = self;
        item.representedObject = option[@"shape"];
        [self.freeformInsertShapeMenu addItem:item];
    }
}

- (NSStackView *)newFreeformModeSection {
    NSStackView *section = [[NSStackView alloc] initWithFrame:NSZeroRect];
    section.translatesAutoresizingMaskIntoConstraints = NO;
    section.orientation = NSUserInterfaceLayoutOrientationVertical;
    section.alignment = NSLayoutAttributeLeading;
    section.spacing = 12.0;
    return section;
}

- (MerrowFreeformInspectorMode)resolvedFreeformInspectorMode {
    if (self.freeformCanvasComponent.insertionKind == MerrowFreeformInsertionKindConnector) {
        return MerrowFreeformInspectorModeAddLink;
    }
    if (self.freeformCanvasComponent.insertionKind == MerrowFreeformInsertionKindNode ||
        self.freeformCanvasComponent.insertionKind == MerrowFreeformInsertionKindSubgraph) {
        return MerrowFreeformInspectorModeAddObject;
    }
    if (self.freeformCanvasComponent.hasSelectedEdge) {
        return MerrowFreeformInspectorModeEdge;
    }
    if (self.freeformCanvasComponent.hasSelectedSubgraph) {
        return MerrowFreeformInspectorModeGroup;
    }
    if (self.freeformCanvasComponent.hasSelectedNode) {
        return MerrowFreeformInspectorModeNode;
    }
    if (self.freeformInspectorModeOverrideActive) {
        return self.freeformInspectorMode;
    }
    return MerrowFreeformInspectorModeCanvas;
}

- (void)setFreeformInspectorModeOverride:(MerrowFreeformInspectorMode)mode {
    self.freeformInspectorMode = mode;
    self.freeformInspectorModeOverrideActive = YES;
}

- (void)clearFreeformInspectorModeOverride {
    self.freeformInspectorModeOverrideActive = NO;
}

- (void)updateFreeformInspectorModeUI {
    MerrowFreeformInspectorMode mode = [self resolvedFreeformInspectorMode];
    self.freeformCanvasModeSection.hidden = mode != MerrowFreeformInspectorModeCanvas;
    self.freeformDefaultsModeSection.hidden = mode != MerrowFreeformInspectorModeCanvas;
    self.freeformAddObjectModeSection.hidden = mode != MerrowFreeformInspectorModeAddObject;
    self.freeformAddLinkModeSection.hidden = mode != MerrowFreeformInspectorModeAddLink;
    self.freeformSelectionModeSection.hidden = !(mode == MerrowFreeformInspectorModeNode || mode == MerrowFreeformInspectorModeGroup || mode == MerrowFreeformInspectorModeEdge);
    self.freeformObjectModeSection.hidden = !(mode == MerrowFreeformInspectorModeNode || mode == MerrowFreeformInspectorModeGroup);
    self.freeformEdgeModeSection.hidden = mode != MerrowFreeformInspectorModeEdge;

    BOOL editingGroup = mode == MerrowFreeformInspectorModeGroup;
    self.freeformObjectLabelCaption.stringValue = editingGroup ? @"Group title" : @"Node label";
    self.freeformObjectSizeCaption.stringValue = editingGroup ? @"Group size" : @"Size";
    self.freeformShapePickerSection.hidden = editingGroup;
    self.freeformNodeLabelField.placeholderString = editingGroup ? @"Select a group to edit its title" : @"Select a node to edit its label";

    NSString *thing = @"Canvas";
    NSString *detail = @"Document-wide defaults and background settings.";
    switch (mode) {
        case MerrowFreeformInspectorModeAddObject:
            thing = @"Add Object";
            detail = @"Choose a shape or group, then place it on the canvas.";
            break;
        case MerrowFreeformInspectorModeAddLink:
            thing = @"Add Link";
            detail = @"Choose source and target objects for a new connector.";
            break;
        case MerrowFreeformInspectorModeNode:
            thing = @"Node";
            detail = @"Editing the selected node.";
            break;
        case MerrowFreeformInspectorModeGroup:
            thing = @"Group";
            detail = @"Editing the selected group.";
            break;
        case MerrowFreeformInspectorModeEdge:
            thing = @"Connector";
            detail = @"Editing the selected connector.";
            break;
        case MerrowFreeformInspectorModeCanvas:
        default:
            break;
    }
    self.freeformInspectorIntroLabel.stringValue = [NSString stringWithFormat:@"Inspecting %@", thing];
    self.freeformInspectorIntroDetailLabel.stringValue = detail;
}

- (void)resetAppStateForIncomingDocument {
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(processEditorChange) object:nil];
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(applySyntaxHighlightingIfCurrent) object:nil];
    [self clearFreeformInspectorModeOverride];
    self.freeformInspectorMode = MerrowFreeformInspectorModeCanvas;
    self.currentDocumentIsFreeform = NO;
    self.freeformModeEnabled = NO;
    self.currentSourcePath = nil;
    [self clearCommandContext];
    [self.freeformCanvasComponent clearDocument];
    [self applyEditingModeUI];
    [self syncFreeformInspectorControls];
}

- (void)blankMermaidWorkspaceForIncomingLoad {
    self.isSynchronizingEditor = YES;
    [self.editorTextView setString:@""];
    [self applySyntaxHighlighting];
    self.editorGeneration += 1;
    [self.editorTextView setSelectedRange:NSMakeRange(0, 0)];
    [self.editorTextView scrollRangeToVisible:NSMakeRange(0, 0)];
    self.isSynchronizingEditor = NO;

    [self.viewerRenderer replaceScene:NULL];
    [self.viewerRenderer resetView];
    [self.viewerView setNeedsDisplay:YES];
    self.statusLabel.stringValue = @"Loading Mermaid document...";
}

- (void)finishLoadingMermaidSource:(NSString *)source fromPath:(NSString *)sourcePath {
    self.freeformModeEnabled = NO;
    self.currentDocumentIsFreeform = NO;
    [self applyEditorSource:source fromPath:sourcePath];
    [self applyEditingModeUI];
    [self processEditorChange];
}

- (void)syncFreeformConnectorControls {
    NSArray<NSDictionary *> *objects = [self.freeformCanvasComponent connectableObjects];
    NSString *selectedObjectId = self.freeformCanvasComponent.selectedConnectableObjectId;
    NSString *currentSourceId = [self selectedObjectIdForPopup:self.freeformConnectorSourcePopup];
    NSString *currentTargetId = [self selectedObjectIdForPopup:self.freeformConnectorTargetPopup];

    [self populateFreeformConnectorPopup:self.freeformConnectorSourcePopup
                             withObjects:objects
                         preferredObject:selectedObjectId ?: currentSourceId];

    NSString *sourceId = [self selectedObjectIdForPopup:self.freeformConnectorSourcePopup];
    [self populateFreeformConnectorPopup:self.freeformConnectorTargetPopup
                             withObjects:objects
                         preferredObject:currentTargetId];

    NSString *targetId = [self selectedObjectIdForPopup:self.freeformConnectorTargetPopup];
    if (sourceId.length > 0 && [sourceId isEqualToString:targetId]) {
        for (NSMenuItem *item in self.freeformConnectorTargetPopup.itemArray) {
            if ([item.representedObject isKindOfClass:[NSString class]] && ![item.representedObject isEqualToString:sourceId]) {
                [self.freeformConnectorTargetPopup selectItem:item];
                break;
            }
        }
    }

    sourceId = [self selectedObjectIdForPopup:self.freeformConnectorSourcePopup];
    targetId = [self selectedObjectIdForPopup:self.freeformConnectorTargetPopup];
    const BOOL hasEnoughObjects = objects.count >= 2;
    self.freeformConnectorSourcePopup.enabled = hasEnoughObjects;
    self.freeformConnectorTargetPopup.enabled = hasEnoughObjects;
    self.freeformAddConnectorButton.enabled = hasEnoughObjects && sourceId.length > 0 && targetId.length > 0 && ![sourceId isEqualToString:targetId];
}

- (IBAction)freeformConnectorPopupSelectionChanged:(id)sender {
    (void)sender;
    [self syncFreeformConnectorControls];
}

- (NSScrollView *)createFreeformToolsScrollView {
    NSStackView *stack = [[NSStackView alloc] initWithFrame:NSZeroRect];
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    stack.appearance = [self darkInspectorAppearance];
    stack.orientation = NSUserInterfaceLayoutOrientationVertical;
    stack.alignment = NSLayoutAttributeLeading;
    stack.spacing = 16.0;
    stack.edgeInsets = NSEdgeInsetsMake(16.0, 16.0, 24.0, 16.0);

        self.freeformInspectorIntroLabel = [self freeformPanelLabel:@"Inspecting Canvas"
                                                                                                                     size:15.0
                                                                                                                 weight:NSFontWeightSemibold
                                                                                                                    color:[NSColor colorWithRed:0.96 green:0.97 blue:0.99 alpha:1.0]];
        [stack addArrangedSubview:self.freeformInspectorIntroLabel];
        self.freeformInspectorIntroDetailLabel = [self freeformPanelLabel:@"Document-wide defaults and background settings."
                                                                                                                                 size:12.0
                                                                                                                             weight:NSFontWeightRegular
                                                                                                                                color:[NSColor colorWithRed:0.79 green:0.82 blue:0.88 alpha:1.0]];
        [stack addArrangedSubview:self.freeformInspectorIntroDetailLabel];

    self.freeformCanvasModeSection = [self newFreeformModeSection];
    [self.freeformCanvasModeSection addArrangedSubview:[self freeformSectionViewWithTitle:@"CANVAS DEFAULTS"
                                                                                    lines:@[
                                                                                        @"Click the canvas with nothing selected to return here.",
                                                                                        @"Set the freeform background and creation defaults for the whole document.",
                                                                                    ]]];
    NSStackView *backgroundRow = [[NSStackView alloc] initWithFrame:NSZeroRect];
    backgroundRow.translatesAutoresizingMaskIntoConstraints = NO;
    backgroundRow.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    backgroundRow.alignment = NSLayoutAttributeCenterY;
    backgroundRow.spacing = 10.0;
    [backgroundRow addArrangedSubview:[self freeformPanelLabel:@"Background"
                                                          size:11.0
                                                        weight:NSFontWeightSemibold
                                                         color:[NSColor colorWithRed:0.55 green:0.60 blue:0.68 alpha:1.0]]];
    self.freeformCanvasBackgroundColorWell = [[NSColorWell alloc] initWithFrame:NSMakeRect(0.0, 0.0, 44.0, 28.0)];
    self.freeformCanvasBackgroundColorWell.translatesAutoresizingMaskIntoConstraints = NO;
    self.freeformCanvasBackgroundColorWell.target = self;
    self.freeformCanvasBackgroundColorWell.action = @selector(applyFreeformCanvasBackgroundColor:);
    [backgroundRow addArrangedSubview:self.freeformCanvasBackgroundColorWell];
    [self.freeformCanvasModeSection addArrangedSubview:backgroundRow];
    [self.freeformCanvasModeSection addArrangedSubview:[self freeformPanelLabel:@"Transparency"
                                                                           size:11.0
                                                                         weight:NSFontWeightSemibold
                                                                          color:[NSColor colorWithRed:0.55 green:0.60 blue:0.68 alpha:1.0]]];
    self.freeformCanvasBackgroundOpacitySlider = [NSSlider sliderWithValue:1.0 minValue:0.0 maxValue:1.0 target:self action:@selector(applyFreeformCanvasBackgroundOpacity:)];
    self.freeformCanvasBackgroundOpacitySlider.translatesAutoresizingMaskIntoConstraints = NO;
    self.freeformCanvasBackgroundOpacitySlider.continuous = YES;
    [self.freeformCanvasModeSection addArrangedSubview:self.freeformCanvasBackgroundOpacitySlider];
    self.freeformCanvasBackgroundOpacityValueLabel = [self freeformPanelLabel:@"100%"
                                                                         size:11.0
                                                                       weight:NSFontWeightRegular
                                                                        color:[NSColor colorWithRed:0.79 green:0.82 blue:0.88 alpha:1.0]];
    [self.freeformCanvasModeSection addArrangedSubview:self.freeformCanvasBackgroundOpacityValueLabel];
    [stack addArrangedSubview:self.freeformCanvasModeSection];

    self.freeformDefaultsModeSection = [self newFreeformModeSection];
    [self.freeformDefaultsModeSection addArrangedSubview:[self freeformSectionViewWithTitle:@"GRAPH DEFAULTS"
                                                                                      lines:@[
                                                                                          @"These defaults apply to newly inserted shapes, groups, and connectors.",
                                                                                          @"Use Insert to switch into add modes, then place objects with the current defaults.",
                                                                                      ]]];
    NSStackView *defaultNodeFillRow = [[NSStackView alloc] initWithFrame:NSZeroRect];
    defaultNodeFillRow.translatesAutoresizingMaskIntoConstraints = NO;
    defaultNodeFillRow.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    defaultNodeFillRow.alignment = NSLayoutAttributeCenterY;
    defaultNodeFillRow.spacing = 10.0;
    [defaultNodeFillRow addArrangedSubview:[self freeformPanelLabel:@"New shape fill" size:11.0 weight:NSFontWeightSemibold color:[NSColor colorWithRed:0.55 green:0.60 blue:0.68 alpha:1.0]]];
    self.freeformDefaultNodeFillColorWell = [[NSColorWell alloc] initWithFrame:NSMakeRect(0.0, 0.0, 44.0, 28.0)];
    self.freeformDefaultNodeFillColorWell.translatesAutoresizingMaskIntoConstraints = NO;
    self.freeformDefaultNodeFillColorWell.target = self;
    self.freeformDefaultNodeFillColorWell.action = @selector(applyFreeformDefaultNodeFillColor:);
    [defaultNodeFillRow addArrangedSubview:self.freeformDefaultNodeFillColorWell];
    [self.freeformDefaultsModeSection addArrangedSubview:defaultNodeFillRow];
    NSStackView *defaultNodeStrokeRow = [[NSStackView alloc] initWithFrame:NSZeroRect];
    defaultNodeStrokeRow.translatesAutoresizingMaskIntoConstraints = NO;
    defaultNodeStrokeRow.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    defaultNodeStrokeRow.alignment = NSLayoutAttributeCenterY;
    defaultNodeStrokeRow.spacing = 10.0;
    [defaultNodeStrokeRow addArrangedSubview:[self freeformPanelLabel:@"New shape stroke" size:11.0 weight:NSFontWeightSemibold color:[NSColor colorWithRed:0.55 green:0.60 blue:0.68 alpha:1.0]]];
    self.freeformDefaultNodeStrokeColorWell = [[NSColorWell alloc] initWithFrame:NSMakeRect(0.0, 0.0, 44.0, 28.0)];
    self.freeformDefaultNodeStrokeColorWell.translatesAutoresizingMaskIntoConstraints = NO;
    self.freeformDefaultNodeStrokeColorWell.target = self;
    self.freeformDefaultNodeStrokeColorWell.action = @selector(applyFreeformDefaultNodeStrokeColor:);
    [defaultNodeStrokeRow addArrangedSubview:self.freeformDefaultNodeStrokeColorWell];
    [self.freeformDefaultsModeSection addArrangedSubview:defaultNodeStrokeRow];
    [self.freeformDefaultsModeSection addArrangedSubview:[self freeformPanelLabel:@"New shape border thickness" size:11.0 weight:NSFontWeightSemibold color:[NSColor colorWithRed:0.55 green:0.60 blue:0.68 alpha:1.0]]];
    self.freeformDefaultNodeStrokeWidthSlider = [NSSlider sliderWithValue:2.0 minValue:1.0 maxValue:12.0 target:self action:@selector(applyFreeformDefaultNodeStrokeWidth:)];
    self.freeformDefaultNodeStrokeWidthSlider.translatesAutoresizingMaskIntoConstraints = NO;
    self.freeformDefaultNodeStrokeWidthSlider.continuous = YES;
    [self.freeformDefaultsModeSection addArrangedSubview:self.freeformDefaultNodeStrokeWidthSlider];
    self.freeformDefaultNodeStrokeWidthValueLabel = [self freeformPanelLabel:@"2.0 pt" size:11.0 weight:NSFontWeightRegular color:[NSColor colorWithRed:0.79 green:0.82 blue:0.88 alpha:1.0]];
    [self.freeformDefaultsModeSection addArrangedSubview:self.freeformDefaultNodeStrokeWidthValueLabel];

    NSStackView *defaultSubgraphFillRow = [[NSStackView alloc] initWithFrame:NSZeroRect];
    defaultSubgraphFillRow.translatesAutoresizingMaskIntoConstraints = NO;
    defaultSubgraphFillRow.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    defaultSubgraphFillRow.alignment = NSLayoutAttributeCenterY;
    defaultSubgraphFillRow.spacing = 10.0;
    [defaultSubgraphFillRow addArrangedSubview:[self freeformPanelLabel:@"New group fill" size:11.0 weight:NSFontWeightSemibold color:[NSColor colorWithRed:0.55 green:0.60 blue:0.68 alpha:1.0]]];
    self.freeformDefaultSubgraphFillColorWell = [[NSColorWell alloc] initWithFrame:NSMakeRect(0.0, 0.0, 44.0, 28.0)];
    self.freeformDefaultSubgraphFillColorWell.translatesAutoresizingMaskIntoConstraints = NO;
    self.freeformDefaultSubgraphFillColorWell.target = self;
    self.freeformDefaultSubgraphFillColorWell.action = @selector(applyFreeformDefaultSubgraphFillColor:);
    [defaultSubgraphFillRow addArrangedSubview:self.freeformDefaultSubgraphFillColorWell];
    [self.freeformDefaultsModeSection addArrangedSubview:defaultSubgraphFillRow];
    NSStackView *defaultSubgraphStrokeRow = [[NSStackView alloc] initWithFrame:NSZeroRect];
    defaultSubgraphStrokeRow.translatesAutoresizingMaskIntoConstraints = NO;
    defaultSubgraphStrokeRow.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    defaultSubgraphStrokeRow.alignment = NSLayoutAttributeCenterY;
    defaultSubgraphStrokeRow.spacing = 10.0;
    [defaultSubgraphStrokeRow addArrangedSubview:[self freeformPanelLabel:@"New group stroke" size:11.0 weight:NSFontWeightSemibold color:[NSColor colorWithRed:0.55 green:0.60 blue:0.68 alpha:1.0]]];
    self.freeformDefaultSubgraphStrokeColorWell = [[NSColorWell alloc] initWithFrame:NSMakeRect(0.0, 0.0, 44.0, 28.0)];
    self.freeformDefaultSubgraphStrokeColorWell.translatesAutoresizingMaskIntoConstraints = NO;
    self.freeformDefaultSubgraphStrokeColorWell.target = self;
    self.freeformDefaultSubgraphStrokeColorWell.action = @selector(applyFreeformDefaultSubgraphStrokeColor:);
    [defaultSubgraphStrokeRow addArrangedSubview:self.freeformDefaultSubgraphStrokeColorWell];
    [self.freeformDefaultsModeSection addArrangedSubview:defaultSubgraphStrokeRow];
    [self.freeformDefaultsModeSection addArrangedSubview:[self freeformPanelLabel:@"New group border thickness" size:11.0 weight:NSFontWeightSemibold color:[NSColor colorWithRed:0.55 green:0.60 blue:0.68 alpha:1.0]]];
    self.freeformDefaultSubgraphStrokeWidthSlider = [NSSlider sliderWithValue:2.0 minValue:1.0 maxValue:12.0 target:self action:@selector(applyFreeformDefaultSubgraphStrokeWidth:)];
    self.freeformDefaultSubgraphStrokeWidthSlider.translatesAutoresizingMaskIntoConstraints = NO;
    self.freeformDefaultSubgraphStrokeWidthSlider.continuous = YES;
    [self.freeformDefaultsModeSection addArrangedSubview:self.freeformDefaultSubgraphStrokeWidthSlider];
    self.freeformDefaultSubgraphStrokeWidthValueLabel = [self freeformPanelLabel:@"2.0 pt" size:11.0 weight:NSFontWeightRegular color:[NSColor colorWithRed:0.79 green:0.82 blue:0.88 alpha:1.0]];
    [self.freeformDefaultsModeSection addArrangedSubview:self.freeformDefaultSubgraphStrokeWidthValueLabel];

    NSStackView *defaultEdgeColorRow = [[NSStackView alloc] initWithFrame:NSZeroRect];
    defaultEdgeColorRow.translatesAutoresizingMaskIntoConstraints = NO;
    defaultEdgeColorRow.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    defaultEdgeColorRow.alignment = NSLayoutAttributeCenterY;
    defaultEdgeColorRow.spacing = 10.0;
    [defaultEdgeColorRow addArrangedSubview:[self freeformPanelLabel:@"New connector color" size:11.0 weight:NSFontWeightSemibold color:[NSColor colorWithRed:0.55 green:0.60 blue:0.68 alpha:1.0]]];
    self.freeformDefaultEdgeColorWell = [[NSColorWell alloc] initWithFrame:NSMakeRect(0.0, 0.0, 44.0, 28.0)];
    self.freeformDefaultEdgeColorWell.translatesAutoresizingMaskIntoConstraints = NO;
    self.freeformDefaultEdgeColorWell.target = self;
    self.freeformDefaultEdgeColorWell.action = @selector(applyFreeformDefaultEdgeColor:);
    [defaultEdgeColorRow addArrangedSubview:self.freeformDefaultEdgeColorWell];
    [self.freeformDefaultsModeSection addArrangedSubview:defaultEdgeColorRow];
    [self.freeformDefaultsModeSection addArrangedSubview:[self freeformPanelLabel:@"New connector thickness" size:11.0 weight:NSFontWeightSemibold color:[NSColor colorWithRed:0.55 green:0.60 blue:0.68 alpha:1.0]]];
    self.freeformDefaultEdgeThicknessSlider = [NSSlider sliderWithValue:2.0 minValue:1.0 maxValue:12.0 target:self action:@selector(applyFreeformDefaultEdgeThickness:)];
    self.freeformDefaultEdgeThicknessSlider.translatesAutoresizingMaskIntoConstraints = NO;
    self.freeformDefaultEdgeThicknessSlider.continuous = YES;
    [self.freeformDefaultsModeSection addArrangedSubview:self.freeformDefaultEdgeThicknessSlider];
    self.freeformDefaultEdgeThicknessValueLabel = [self freeformPanelLabel:@"2.0 pt" size:11.0 weight:NSFontWeightRegular color:[NSColor colorWithRed:0.79 green:0.82 blue:0.88 alpha:1.0]];
    [self.freeformDefaultsModeSection addArrangedSubview:self.freeformDefaultEdgeThicknessValueLabel];
    [self.freeformDefaultsModeSection addArrangedSubview:[self freeformPanelLabel:@"New connector pattern" size:11.0 weight:NSFontWeightSemibold color:[NSColor colorWithRed:0.55 green:0.60 blue:0.68 alpha:1.0]]];
    self.freeformDefaultEdgePatternPopup = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(0.0, 0.0, 220.0, 26.0) pullsDown:NO];
    self.freeformDefaultEdgePatternPopup.translatesAutoresizingMaskIntoConstraints = NO;
    [self.freeformDefaultEdgePatternPopup addItemsWithTitles:@[@"Solid", @"Dashed", @"Dotted", @"Thick"]];
    self.freeformDefaultEdgePatternPopup.target = self;
    self.freeformDefaultEdgePatternPopup.action = @selector(applyFreeformDefaultEdgePattern:);
    [self.freeformDefaultsModeSection addArrangedSubview:self.freeformDefaultEdgePatternPopup];
    [self.freeformDefaultsModeSection addArrangedSubview:[self freeformPanelLabel:@"New connector arrows" size:11.0 weight:NSFontWeightSemibold color:[NSColor colorWithRed:0.55 green:0.60 blue:0.68 alpha:1.0]]];
    self.freeformDefaultEdgeArrowPopup = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(0.0, 0.0, 220.0, 26.0) pullsDown:NO];
    self.freeformDefaultEdgeArrowPopup.translatesAutoresizingMaskIntoConstraints = NO;
    [self.freeformDefaultEdgeArrowPopup addItemsWithTitles:@[@"None", @"Forward", @"Reverse", @"Both"]];
    self.freeformDefaultEdgeArrowPopup.target = self;
    self.freeformDefaultEdgeArrowPopup.action = @selector(applyFreeformDefaultEdgeArrowMode:);
    [self.freeformDefaultsModeSection addArrangedSubview:self.freeformDefaultEdgeArrowPopup];
    [stack addArrangedSubview:self.freeformDefaultsModeSection];

    self.freeformShapePickerSection = [self newFreeformModeSection];
    [self.freeformShapePickerSection addArrangedSubview:[self freeformPanelLabel:@"Shape" size:11.0 weight:NSFontWeightSemibold color:[NSColor colorWithRed:0.55 green:0.60 blue:0.68 alpha:1.0]]];
    self.freeformShapePopup = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(0.0, 0.0, 220.0, 26.0) pullsDown:NO];
    self.freeformShapePopup.translatesAutoresizingMaskIntoConstraints = NO;
    self.freeformShapePopup.target = self;
    self.freeformShapePopup.action = @selector(applyFreeformSelectedShape:);
    [self rebuildFreeformShapePopupOptions];
    [self.freeformShapePickerSection addArrangedSubview:self.freeformShapePopup];
    [stack addArrangedSubview:self.freeformShapePickerSection];

    self.freeformAddObjectModeSection = [self newFreeformModeSection];
    [self.freeformAddObjectModeSection addArrangedSubview:[self freeformSectionViewWithTitle:@"ADD OBJECT"
                                                                                       lines:@[
                                                                                           @"Use Insert > Add Object or the buttons below to enter placement mode.",
                                                                                           @"If a group is selected, new objects are nested inside that group.",
                                                                                       ]]];
    NSStackView *createButtonsRow = [[NSStackView alloc] initWithFrame:NSZeroRect];
    createButtonsRow.translatesAutoresizingMaskIntoConstraints = NO;
    createButtonsRow.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    createButtonsRow.alignment = NSLayoutAttributeCenterY;
    createButtonsRow.spacing = 8.0;
    self.freeformAddShapeButton = [NSButton buttonWithTitle:@"Add Shape" target:self action:@selector(beginFreeformAddShape:)];
    self.freeformAddShapeButton.translatesAutoresizingMaskIntoConstraints = NO;
    [createButtonsRow addArrangedSubview:self.freeformAddShapeButton];
    self.freeformAddGroupButton = [NSButton buttonWithTitle:@"Add Group" target:self action:@selector(beginFreeformAddGroup:)];
    self.freeformAddGroupButton.translatesAutoresizingMaskIntoConstraints = NO;
    [createButtonsRow addArrangedSubview:self.freeformAddGroupButton];
    self.freeformCancelCreateButton = [NSButton buttonWithTitle:@"Cancel" target:self action:@selector(cancelFreeformInsertion:)];
    self.freeformCancelCreateButton.translatesAutoresizingMaskIntoConstraints = NO;
    self.freeformCancelCreateButton.enabled = NO;
    [createButtonsRow addArrangedSubview:self.freeformCancelCreateButton];
    [self.freeformAddObjectModeSection addArrangedSubview:createButtonsRow];
    self.freeformCreateStatusLabel = [self freeformPanelLabel:@"Choose Add Shape or Add Group, then click the canvas to place it." size:12.0 weight:NSFontWeightRegular color:[NSColor colorWithRed:0.87 green:0.89 blue:0.93 alpha:1.0]];
    [self.freeformAddObjectModeSection addArrangedSubview:self.freeformCreateStatusLabel];
    [stack addArrangedSubview:self.freeformAddObjectModeSection];

    self.freeformAddLinkModeSection = [self newFreeformModeSection];
    [self.freeformAddLinkModeSection addArrangedSubview:[self freeformSectionViewWithTitle:@"ADD LINK"
                                                                                     lines:@[
                                                                                         @"Use Insert > Add Link to stay focused on connector creation.",
                                                                                         @"Pick a source and target here, or start a connector from the canvas.",
                                                                                     ]]];
    self.freeformConnectorSourcePopup = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(0.0, 0.0, 220.0, 26.0) pullsDown:NO];
    self.freeformConnectorSourcePopup.translatesAutoresizingMaskIntoConstraints = NO;
    self.freeformConnectorSourcePopup.target = self;
    self.freeformConnectorSourcePopup.action = @selector(freeformConnectorPopupSelectionChanged:);
    [self.freeformAddLinkModeSection addArrangedSubview:[self freeformPanelLabel:@"From" size:11.0 weight:NSFontWeightSemibold color:[NSColor colorWithRed:0.55 green:0.60 blue:0.68 alpha:1.0]]];
    [self.freeformAddLinkModeSection addArrangedSubview:self.freeformConnectorSourcePopup];
    self.freeformConnectorTargetPopup = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(0.0, 0.0, 220.0, 26.0) pullsDown:NO];
    self.freeformConnectorTargetPopup.translatesAutoresizingMaskIntoConstraints = NO;
    self.freeformConnectorTargetPopup.target = self;
    self.freeformConnectorTargetPopup.action = @selector(freeformConnectorPopupSelectionChanged:);
    [self.freeformAddLinkModeSection addArrangedSubview:[self freeformPanelLabel:@"To" size:11.0 weight:NSFontWeightSemibold color:[NSColor colorWithRed:0.55 green:0.60 blue:0.68 alpha:1.0]]];
    [self.freeformAddLinkModeSection addArrangedSubview:self.freeformConnectorTargetPopup];
    self.freeformAddConnectorButton = [NSButton buttonWithTitle:@"Add Connector" target:self action:@selector(addFreeformConnector:)];
    self.freeformAddConnectorButton.translatesAutoresizingMaskIntoConstraints = NO;
    self.freeformAddConnectorButton.enabled = NO;
    [self.freeformAddLinkModeSection addArrangedSubview:self.freeformAddConnectorButton];
    [stack addArrangedSubview:self.freeformAddLinkModeSection];

    self.freeformSelectionModeSection = [self newFreeformModeSection];
    [self.freeformSelectionModeSection addArrangedSubview:[self freeformSectionViewWithTitle:@"SELECTION"
                                                                                       lines:@[
                                                                                           @"Node, group, and connector inspectors are shown one at a time.",
                                                                                       ]]];
    self.freeformSelectionLabel = [self freeformPanelLabel:@"No selection" size:12.0 weight:NSFontWeightSemibold color:[NSColor colorWithRed:0.96 green:0.97 blue:0.99 alpha:1.0]];
    [self.freeformSelectionModeSection addArrangedSubview:self.freeformSelectionLabel];
    [stack addArrangedSubview:self.freeformSelectionModeSection];

    self.freeformObjectModeSection = [self newFreeformModeSection];
    self.freeformObjectLabelCaption = [self freeformPanelLabel:@"Node label" size:11.0 weight:NSFontWeightSemibold color:[NSColor colorWithRed:0.55 green:0.60 blue:0.68 alpha:1.0]];
    [self.freeformObjectModeSection addArrangedSubview:self.freeformObjectLabelCaption];
    self.freeformNodeLabelField = [[NSTextField alloc] initWithFrame:NSZeroRect];
    self.freeformNodeLabelField.translatesAutoresizingMaskIntoConstraints = NO;
    self.freeformNodeLabelField.font = [NSFont systemFontOfSize:12.0 weight:NSFontWeightRegular];
    self.freeformNodeLabelField.placeholderString = @"Select a node to edit its label";
    self.freeformNodeLabelField.target = self;
    self.freeformNodeLabelField.action = @selector(applyFreeformNodeLabel:);
    self.freeformNodeLabelField.enabled = NO;
    [self.freeformNodeLabelField.widthAnchor constraintGreaterThanOrEqualToConstant:240.0].active = YES;
    [self.freeformObjectModeSection addArrangedSubview:self.freeformNodeLabelField];
    self.freeformObjectSizeCaption = [self freeformPanelLabel:@"Size" size:11.0 weight:NSFontWeightSemibold color:[NSColor colorWithRed:0.55 green:0.60 blue:0.68 alpha:1.0]];
    [self.freeformObjectModeSection addArrangedSubview:self.freeformObjectSizeCaption];
    NSStackView *sizeRow = [[NSStackView alloc] initWithFrame:NSZeroRect];
    sizeRow.translatesAutoresizingMaskIntoConstraints = NO;
    sizeRow.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    sizeRow.alignment = NSLayoutAttributeCenterY;
    sizeRow.spacing = 8.0;
    [sizeRow addArrangedSubview:[self freeformPanelLabel:@"W" size:11.0 weight:NSFontWeightSemibold color:[NSColor colorWithRed:0.55 green:0.60 blue:0.68 alpha:1.0]]];
    self.freeformWidthField = [[NSTextField alloc] initWithFrame:NSMakeRect(0.0, 0.0, 72.0, 24.0)];
    self.freeformWidthField.translatesAutoresizingMaskIntoConstraints = NO;
    self.freeformWidthField.font = [NSFont systemFontOfSize:12.0 weight:NSFontWeightRegular];
    self.freeformWidthField.placeholderString = @"Width";
    self.freeformWidthField.target = self;
    self.freeformWidthField.action = @selector(applyFreeformObjectWidth:);
    self.freeformWidthField.enabled = NO;
    [self.freeformWidthField.widthAnchor constraintEqualToConstant:78.0].active = YES;
    [sizeRow addArrangedSubview:self.freeformWidthField];
    [sizeRow addArrangedSubview:[self freeformPanelLabel:@"H" size:11.0 weight:NSFontWeightSemibold color:[NSColor colorWithRed:0.55 green:0.60 blue:0.68 alpha:1.0]]];
    self.freeformHeightField = [[NSTextField alloc] initWithFrame:NSMakeRect(0.0, 0.0, 72.0, 24.0)];
    self.freeformHeightField.translatesAutoresizingMaskIntoConstraints = NO;
    self.freeformHeightField.font = [NSFont systemFontOfSize:12.0 weight:NSFontWeightRegular];
    self.freeformHeightField.placeholderString = @"Height";
    self.freeformHeightField.target = self;
    self.freeformHeightField.action = @selector(applyFreeformObjectHeight:);
    self.freeformHeightField.enabled = NO;
    [self.freeformHeightField.widthAnchor constraintEqualToConstant:78.0].active = YES;
    [sizeRow addArrangedSubview:self.freeformHeightField];
    [self.freeformObjectModeSection addArrangedSubview:sizeRow];
    NSStackView *fillRow = [[NSStackView alloc] initWithFrame:NSZeroRect];
    fillRow.translatesAutoresizingMaskIntoConstraints = NO;
    fillRow.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    fillRow.alignment = NSLayoutAttributeCenterY;
    fillRow.spacing = 10.0;
    [fillRow addArrangedSubview:[self freeformPanelLabel:@"Fill" size:11.0 weight:NSFontWeightSemibold color:[NSColor colorWithRed:0.55 green:0.60 blue:0.68 alpha:1.0]]];
    self.freeformFillColorWell = [[NSColorWell alloc] initWithFrame:NSMakeRect(0.0, 0.0, 44.0, 28.0)];
    self.freeformFillColorWell.translatesAutoresizingMaskIntoConstraints = NO;
    self.freeformFillColorWell.target = self;
    self.freeformFillColorWell.action = @selector(applyFreeformFillColor:);
    self.freeformFillColorWell.enabled = NO;
    [fillRow addArrangedSubview:self.freeformFillColorWell];
    [self.freeformObjectModeSection addArrangedSubview:fillRow];
    NSStackView *strokeRow = [[NSStackView alloc] initWithFrame:NSZeroRect];
    strokeRow.translatesAutoresizingMaskIntoConstraints = NO;
    strokeRow.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    strokeRow.alignment = NSLayoutAttributeCenterY;
    strokeRow.spacing = 10.0;
    [strokeRow addArrangedSubview:[self freeformPanelLabel:@"Stroke" size:11.0 weight:NSFontWeightSemibold color:[NSColor colorWithRed:0.55 green:0.60 blue:0.68 alpha:1.0]]];
    self.freeformStrokeColorWell = [[NSColorWell alloc] initWithFrame:NSMakeRect(0.0, 0.0, 44.0, 28.0)];
    self.freeformStrokeColorWell.translatesAutoresizingMaskIntoConstraints = NO;
    self.freeformStrokeColorWell.target = self;
    self.freeformStrokeColorWell.action = @selector(applyFreeformStrokeColor:);
    self.freeformStrokeColorWell.enabled = NO;
    [strokeRow addArrangedSubview:self.freeformStrokeColorWell];
    [self.freeformObjectModeSection addArrangedSubview:strokeRow];
    [self.freeformObjectModeSection addArrangedSubview:[self freeformPanelLabel:@"Border thickness" size:11.0 weight:NSFontWeightSemibold color:[NSColor colorWithRed:0.55 green:0.60 blue:0.68 alpha:1.0]]];
    self.freeformStrokeWidthSlider = [NSSlider sliderWithValue:2.0 minValue:1.0 maxValue:12.0 target:self action:@selector(applyFreeformStrokeWidth:)];
    self.freeformStrokeWidthSlider.translatesAutoresizingMaskIntoConstraints = NO;
    self.freeformStrokeWidthSlider.continuous = YES;
    self.freeformStrokeWidthSlider.enabled = NO;
    [self.freeformObjectModeSection addArrangedSubview:self.freeformStrokeWidthSlider];
    self.freeformStrokeWidthValueLabel = [self freeformPanelLabel:@"2.0 pt" size:11.0 weight:NSFontWeightRegular color:[NSColor colorWithRed:0.79 green:0.82 blue:0.88 alpha:1.0]];
    [self.freeformObjectModeSection addArrangedSubview:self.freeformStrokeWidthValueLabel];
    [stack addArrangedSubview:self.freeformObjectModeSection];

    self.freeformEdgeModeSection = [self newFreeformModeSection];
    [self.freeformEdgeModeSection addArrangedSubview:[self freeformSectionViewWithTitle:@"CONNECTOR"
                                                                                 lines:@[
                                                                                     @"Connector editing is only shown when a connector is selected.",
                                                                                 ]]];
    [self.freeformEdgeModeSection addArrangedSubview:[self freeformPanelLabel:@"Connector label" size:11.0 weight:NSFontWeightSemibold color:[NSColor colorWithRed:0.55 green:0.60 blue:0.68 alpha:1.0]]];
    self.freeformEdgeLabelField = [[NSTextField alloc] initWithFrame:NSZeroRect];
    self.freeformEdgeLabelField.translatesAutoresizingMaskIntoConstraints = NO;
    self.freeformEdgeLabelField.font = [NSFont systemFontOfSize:12.0 weight:NSFontWeightRegular];
    self.freeformEdgeLabelField.placeholderString = @"Select a connector to edit its label";
    self.freeformEdgeLabelField.target = self;
    self.freeformEdgeLabelField.action = @selector(applyFreeformEdgeLabel:);
    self.freeformEdgeLabelField.enabled = NO;
    [self.freeformEdgeLabelField.widthAnchor constraintGreaterThanOrEqualToConstant:240.0].active = YES;
    [self.freeformEdgeModeSection addArrangedSubview:self.freeformEdgeLabelField];
    NSStackView *edgeColorRow = [[NSStackView alloc] initWithFrame:NSZeroRect];
    edgeColorRow.translatesAutoresizingMaskIntoConstraints = NO;
    edgeColorRow.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    edgeColorRow.alignment = NSLayoutAttributeCenterY;
    edgeColorRow.spacing = 10.0;
    [edgeColorRow addArrangedSubview:[self freeformPanelLabel:@"Connector color" size:11.0 weight:NSFontWeightSemibold color:[NSColor colorWithRed:0.55 green:0.60 blue:0.68 alpha:1.0]]];
    self.freeformEdgeColorWell = [[NSColorWell alloc] initWithFrame:NSMakeRect(0.0, 0.0, 44.0, 28.0)];
    self.freeformEdgeColorWell.translatesAutoresizingMaskIntoConstraints = NO;
    self.freeformEdgeColorWell.target = self;
    self.freeformEdgeColorWell.action = @selector(applyFreeformEdgeColor:);
    self.freeformEdgeColorWell.enabled = NO;
    [edgeColorRow addArrangedSubview:self.freeformEdgeColorWell];
    [self.freeformEdgeModeSection addArrangedSubview:edgeColorRow];
    [self.freeformEdgeModeSection addArrangedSubview:[self freeformPanelLabel:@"Connector thickness" size:11.0 weight:NSFontWeightSemibold color:[NSColor colorWithRed:0.55 green:0.60 blue:0.68 alpha:1.0]]];
    self.freeformEdgeThicknessSlider = [NSSlider sliderWithValue:2.0 minValue:1.0 maxValue:12.0 target:self action:@selector(applyFreeformEdgeThickness:)];
    self.freeformEdgeThicknessSlider.translatesAutoresizingMaskIntoConstraints = NO;
    self.freeformEdgeThicknessSlider.continuous = YES;
    self.freeformEdgeThicknessSlider.enabled = NO;
    [self.freeformEdgeModeSection addArrangedSubview:self.freeformEdgeThicknessSlider];
    self.freeformEdgeThicknessValueLabel = [self freeformPanelLabel:@"2.0 pt" size:11.0 weight:NSFontWeightRegular color:[NSColor colorWithRed:0.79 green:0.82 blue:0.88 alpha:1.0]];
    [self.freeformEdgeModeSection addArrangedSubview:self.freeformEdgeThicknessValueLabel];
    [self.freeformEdgeModeSection addArrangedSubview:[self freeformPanelLabel:@"Connector pattern" size:11.0 weight:NSFontWeightSemibold color:[NSColor colorWithRed:0.55 green:0.60 blue:0.68 alpha:1.0]]];
    self.freeformEdgePatternPopup = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(0.0, 0.0, 220.0, 26.0) pullsDown:NO];
    self.freeformEdgePatternPopup.translatesAutoresizingMaskIntoConstraints = NO;
    [self.freeformEdgePatternPopup addItemsWithTitles:@[@"Solid", @"Dashed", @"Dotted", @"Thick"]];
    self.freeformEdgePatternPopup.target = self;
    self.freeformEdgePatternPopup.action = @selector(applyFreeformEdgePattern:);
    self.freeformEdgePatternPopup.enabled = NO;
    [self.freeformEdgeModeSection addArrangedSubview:self.freeformEdgePatternPopup];
    [self.freeformEdgeModeSection addArrangedSubview:[self freeformPanelLabel:@"Arrow direction" size:11.0 weight:NSFontWeightSemibold color:[NSColor colorWithRed:0.55 green:0.60 blue:0.68 alpha:1.0]]];
    self.freeformEdgeArrowPopup = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(0.0, 0.0, 220.0, 26.0) pullsDown:NO];
    self.freeformEdgeArrowPopup.translatesAutoresizingMaskIntoConstraints = NO;
    [self.freeformEdgeArrowPopup addItemsWithTitles:@[@"None", @"Forward", @"Reverse", @"Both"]];
    self.freeformEdgeArrowPopup.target = self;
    self.freeformEdgeArrowPopup.action = @selector(applyFreeformEdgeArrowMode:);
    self.freeformEdgeArrowPopup.enabled = NO;
    [self.freeformEdgeModeSection addArrangedSubview:self.freeformEdgeArrowPopup];
    [stack addArrangedSubview:self.freeformEdgeModeSection];

    NSView *document = [[NSView alloc] initWithFrame:NSZeroRect];
    document.translatesAutoresizingMaskIntoConstraints = NO;
    document.appearance = [self darkInspectorAppearance];
    [document addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[
        [stack.leadingAnchor constraintEqualToAnchor:document.leadingAnchor],
        [stack.trailingAnchor constraintEqualToAnchor:document.trailingAnchor],
        [stack.topAnchor constraintEqualToAnchor:document.topAnchor],
        [stack.bottomAnchor constraintEqualToAnchor:document.bottomAnchor],
        [stack.widthAnchor constraintEqualToAnchor:document.widthAnchor],
    ]];

    NSScrollView *scrollView = [[NSScrollView alloc] initWithFrame:NSZeroRect];
    scrollView.translatesAutoresizingMaskIntoConstraints = NO;
    scrollView.hasVerticalScroller = YES;
    scrollView.hasHorizontalScroller = NO;
    scrollView.autohidesScrollers = YES;
    scrollView.borderType = NSNoBorder;
    scrollView.backgroundColor = [NSColor colorWithRed:0.10 green:0.11 blue:0.13 alpha:1.0];
    scrollView.drawsBackground = YES;
    scrollView.appearance = [self darkInspectorAppearance];
    scrollView.documentView = document;
    [self applyDarkInspectorControlThemeToView:document];
    [self updateFreeformInspectorModeUI];
    return scrollView;
}

- (void)syncFreeformInspectorControls {
    [self rebuildFreeformShapePopupOptions];
    [self rebuildFreeformInsertMenu];
    [self updateFreeformInspectorModeUI];
    self.freeformCreateStatusLabel.stringValue = self.freeformCanvasComponent.insertionSummary ?: @"";
    self.freeformCancelCreateButton.enabled = self.freeformCanvasComponent.insertionModeActive;
    self.freeformCanvasBackgroundColorWell.color = self.freeformCanvasComponent.canvasBackgroundColor ?: [NSColor whiteColor];
    self.freeformCanvasBackgroundOpacitySlider.doubleValue = self.freeformCanvasComponent.canvasBackgroundOpacity;
    self.freeformCanvasBackgroundOpacityValueLabel.stringValue = [NSString stringWithFormat:@"%.0f%%", self.freeformCanvasComponent.canvasBackgroundOpacity * 100.0];
    self.freeformDefaultNodeFillColorWell.color = self.freeformCanvasComponent.defaultNodeFillColor ?: [NSColor whiteColor];
    self.freeformDefaultNodeStrokeColorWell.color = self.freeformCanvasComponent.defaultNodeStrokeColor ?: [NSColor blackColor];
    self.freeformDefaultNodeStrokeWidthSlider.doubleValue = self.freeformCanvasComponent.defaultNodeStrokeWidth;
    self.freeformDefaultNodeStrokeWidthValueLabel.stringValue = [NSString stringWithFormat:@"%.1f pt", self.freeformCanvasComponent.defaultNodeStrokeWidth];
    self.freeformDefaultSubgraphFillColorWell.color = self.freeformCanvasComponent.defaultSubgraphFillColor ?: [NSColor whiteColor];
    self.freeformDefaultSubgraphStrokeColorWell.color = self.freeformCanvasComponent.defaultSubgraphStrokeColor ?: [NSColor blackColor];
    self.freeformDefaultSubgraphStrokeWidthSlider.doubleValue = self.freeformCanvasComponent.defaultSubgraphStrokeWidth;
    self.freeformDefaultSubgraphStrokeWidthValueLabel.stringValue = [NSString stringWithFormat:@"%.1f pt", self.freeformCanvasComponent.defaultSubgraphStrokeWidth];
    self.freeformDefaultEdgeColorWell.color = self.freeformCanvasComponent.defaultEdgeStrokeColor ?: [NSColor blackColor];
    self.freeformDefaultEdgeThicknessSlider.doubleValue = self.freeformCanvasComponent.defaultEdgeThickness;
    self.freeformDefaultEdgeThicknessValueLabel.stringValue = [NSString stringWithFormat:@"%.1f pt", self.freeformCanvasComponent.defaultEdgeThickness];
    [self.freeformDefaultEdgePatternPopup selectItemAtIndex:MAX(0, MIN(self.freeformCanvasComponent.defaultEdgeLineStyle, 3))];
    [self.freeformDefaultEdgeArrowPopup selectItemAtIndex:MAX(0, MIN(self.freeformCanvasComponent.defaultEdgeArrowMode, 3))];
    self.freeformDefaultEdgeArrowPopup.enabled = self.freeformCanvasComponent.graphType != MerrowFreeformGraphTypeER;
    [self syncFreeformConnectorControls];

    const BOOL hasSelection = self.freeformCanvasComponent.hasSelectedNode || self.freeformCanvasComponent.hasSelectedSubgraph;
    const BOOL hasNodeSelection = self.freeformCanvasComponent.hasSelectedNode;
    const BOOL hasEdgeSelection = self.freeformCanvasComponent.hasSelectedEdge;
    self.freeformNodeLabelField.enabled = hasSelection;
    self.freeformWidthField.enabled = hasSelection;
    self.freeformHeightField.enabled = hasSelection;
    self.freeformFillColorWell.enabled = hasSelection;
    self.freeformStrokeColorWell.enabled = hasSelection;
    self.freeformStrokeWidthSlider.enabled = hasSelection;
    self.freeformEdgeLabelField.enabled = hasEdgeSelection;
    self.freeformEdgeColorWell.enabled = hasEdgeSelection;
    self.freeformEdgeThicknessSlider.enabled = hasEdgeSelection;
    self.freeformEdgePatternPopup.enabled = hasEdgeSelection;
    self.freeformEdgeArrowPopup.enabled = hasEdgeSelection;

    if (!hasSelection) {
        self.freeformNodeLabelField.stringValue = @"";
        self.freeformWidthField.stringValue = @"";
        self.freeformHeightField.stringValue = @"";
        self.freeformStrokeWidthValueLabel.stringValue = @"-";
    } else {
        self.freeformNodeLabelField.stringValue = self.freeformCanvasComponent.selectedNodeLabel ?: @"";
        self.freeformWidthField.stringValue = [NSString stringWithFormat:@"%.0f", self.freeformCanvasComponent.selectedObjectWidth];
        self.freeformHeightField.stringValue = [NSString stringWithFormat:@"%.0f", self.freeformCanvasComponent.selectedObjectHeight];
        self.freeformFillColorWell.color = self.freeformCanvasComponent.selectedNodeFillColor ?: [NSColor whiteColor];
        self.freeformStrokeColorWell.color = self.freeformCanvasComponent.selectedNodeStrokeColor ?: [NSColor blackColor];
        self.freeformStrokeWidthSlider.doubleValue = self.freeformCanvasComponent.selectedNodeStrokeWidth;
        self.freeformStrokeWidthValueLabel.stringValue = [NSString stringWithFormat:@"%.1f pt", self.freeformCanvasComponent.selectedNodeStrokeWidth];
    }

    if (hasNodeSelection) {
        NSNumber *selectedShape = @(self.freeformCanvasComponent.selectedNodeShape);
        for (NSMenuItem *item in self.freeformShapePopup.itemArray) {
            if ([item.representedObject isKindOfClass:[NSNumber class]] && [item.representedObject isEqualToNumber:selectedShape]) {
                [self.freeformShapePopup selectItem:item];
                break;
            }
        }
    }

    if (!hasEdgeSelection) {
        self.freeformEdgeLabelField.stringValue = @"";
        self.freeformEdgeThicknessValueLabel.stringValue = @"-";
        [self.freeformEdgePatternPopup selectItemAtIndex:0];
        [self.freeformEdgeArrowPopup selectItemAtIndex:0];
    } else {
        self.freeformEdgeLabelField.stringValue = self.freeformCanvasComponent.selectedEdgeLabel ?: @"";
        self.freeformEdgeColorWell.color = self.freeformCanvasComponent.selectedEdgeStrokeColor ?: [NSColor blackColor];
        self.freeformEdgeThicknessSlider.doubleValue = self.freeformCanvasComponent.selectedEdgeThickness;
        self.freeformEdgeThicknessValueLabel.stringValue = [NSString stringWithFormat:@"%.1f pt", self.freeformCanvasComponent.selectedEdgeThickness];
        [self.freeformEdgePatternPopup selectItemAtIndex:MAX(0, MIN(self.freeformCanvasComponent.selectedEdgeLineStyle, 3))];
        [self.freeformEdgeArrowPopup selectItemAtIndex:MAX(0, MIN(self.freeformCanvasComponent.selectedEdgeArrowMode, 3))];
    }

    [self updateFreeformInspectorModeUI];
}

- (BOOL)isFreeformGraphPath:(NSString *)path {
    NSString *extension = [path.pathExtension lowercaseString];
    return [extension isEqualToString:@"ffm"] || [extension isEqualToString:@"merrowgraph"];
}

- (NSString *)defaultFreeformSourcePlaceholder {
    return @"%% Freeform graph document\n%% Use Diagram > Mode > Freeform Canvas to edit this custom graph.\n";
}

- (BOOL)writeFreeformDocumentToPath:(NSString *)targetPath error:(NSError **)error {
    NSData *graphData = [self.freeformCanvasComponent serializedDocumentDataWithError:error];
    if (!graphData) {
        return NO;
    }

    NSString *source = self.editorTextView.string ?: @"";
    NSDictionary *document = @{
        @"format": @"merrow-ffm-v1",
        @"mermaidSource": source,
        @"freeformGraph": graphData,
    };

    NSData *data = [NSPropertyListSerialization dataWithPropertyList:document
                                                              format:NSPropertyListBinaryFormat_v1_0
                                                             options:0
                                                               error:error];
    if (!data) {
        return NO;
    }

    const BOOL ok = [data writeToFile:targetPath options:NSDataWritingAtomic error:error];
    if (ok) {
        self.currentDocumentIsFreeform = YES;
        self.currentSourcePath = [targetPath copy];
        [self markDocumentEdited:NO];
        self.statusLabel.stringValue = [NSString stringWithFormat:@"Saved %@", self.currentSourcePath.lastPathComponent ?: @"document"];
    }
    return ok;
}

- (BOOL)loadFreeformDocumentFromPath:(NSString *)sourcePath {
    [self resetAppStateForIncomingDocument];
    NSError *error = nil;
    NSData *data = [NSData dataWithContentsOfFile:sourcePath options:0 error:&error];
    if (!data) {
        self.statusLabel.stringValue = [NSString stringWithFormat:@"Failed to load graph: %@", error.localizedDescription ?: @"unknown error"];
        return NO;
    }

    NSData *graphData = nil;
    NSString *source = nil;
    NSPropertyListFormat format = NSPropertyListBinaryFormat_v1_0;
    id root = [NSPropertyListSerialization propertyListWithData:data
                                                        options:NSPropertyListMutableContainersAndLeaves
                                                         format:&format
                                                          error:nil];
    if ([root isKindOfClass:[NSDictionary class]] && [[[root[@"format"] description] lowercaseString] isEqualToString:@"merrow-ffm-v1"]) {
        source = [root[@"mermaidSource"] isKindOfClass:[NSString class]] ? root[@"mermaidSource"] : @"";
        graphData = [root[@"freeformGraph"] isKindOfClass:[NSData class]] ? root[@"freeformGraph"] : nil;
        if (!graphData) {
            self.statusLabel.stringValue = @"Failed to load graph: missing freeform graph payload.";
            return NO;
        }
    } else {
        graphData = data;
        source = [self defaultFreeformSourcePlaceholder];
    }

    if (![self.freeformCanvasComponent loadSerializedDocumentData:graphData error:&error]) {
        self.statusLabel.stringValue = [NSString stringWithFormat:@"Failed to load graph: %@", error.localizedDescription ?: @"unknown error"];
        return NO;
    }

    [self applyEditorSource:source ?: [self defaultFreeformSourcePlaceholder] fromPath:sourcePath];
    self.currentDocumentIsFreeform = YES;
    self.freeformModeEnabled = YES;
    [self applyEditingModeUI];
    [self syncFreeformInspectorControls];
    self.statusLabel.stringValue = [NSString stringWithFormat:@"Loaded %@", sourcePath.lastPathComponent ?: @"graph"];
    return YES;
}

- (void)mountViewerPaneBodyView:(NSView *)bodyView {
    if (!self.viewerPaneContentHost || !bodyView) return;

    for (NSView *subview in [self.viewerPaneContentHost.subviews copy]) {
        [subview removeFromSuperview];
    }

    bodyView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.viewerPaneContentHost addSubview:bodyView];
    [NSLayoutConstraint activateConstraints:@[
        [bodyView.leadingAnchor constraintEqualToAnchor:self.viewerPaneContentHost.leadingAnchor],
        [bodyView.trailingAnchor constraintEqualToAnchor:self.viewerPaneContentHost.trailingAnchor],
        [bodyView.topAnchor constraintEqualToAnchor:self.viewerPaneContentHost.topAnchor],
        [bodyView.bottomAnchor constraintEqualToAnchor:self.viewerPaneContentHost.bottomAnchor],
    ]];
}

- (void)mountEditorPaneBodyView:(NSView *)bodyView {
    if (!self.editorPaneContentHost || !bodyView) return;

    for (NSView *subview in [self.editorPaneContentHost.subviews copy]) {
        [subview removeFromSuperview];
    }

    bodyView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.editorPaneContentHost addSubview:bodyView];
    [NSLayoutConstraint activateConstraints:@[
        [bodyView.leadingAnchor constraintEqualToAnchor:self.editorPaneContentHost.leadingAnchor],
        [bodyView.trailingAnchor constraintEqualToAnchor:self.editorPaneContentHost.trailingAnchor],
        [bodyView.topAnchor constraintEqualToAnchor:self.editorPaneContentHost.topAnchor],
        [bodyView.bottomAnchor constraintEqualToAnchor:self.editorPaneContentHost.bottomAnchor],
    ]];
}

- (void)applyEditingModeUI {
    if (self.freeformModeEnabled) {
        self.viewerPaneTitleLabel.stringValue = @"Editable Canvas";
        self.viewerPaneSubtitleLabel.stringValue = @"Reusable freeform object-graph component with direct selection and drag editing";
        [self mountViewerPaneBodyView:self.freeformCanvasComponent];
        self.editorPaneTitleLabel.stringValue = @"Freeform Canvas";
        self.editorPaneSubtitleLabel.stringValue = @"Tools and inspector workspace for custom object-graph editing";
        [self mountEditorPaneBodyView:self.freeformToolsScrollView];
        self.commandField.hidden = YES;
        self.commandButton.hidden = YES;
        self.contextLabel.hidden = YES;
        self.mermaidModeMenuItem.state = NSControlStateValueOff;
        self.freeformModeMenuItem.state = NSControlStateValueOn;
        [self.window makeFirstResponder:self.freeformCanvasComponent];
    } else {
        self.viewerPaneTitleLabel.stringValue = @"Diagram View";
        self.viewerPaneSubtitleLabel.stringValue = @"Direct AppKit vector preview with pan and zoom";
        [self mountViewerPaneBodyView:self.viewerView];
        self.editorPaneTitleLabel.stringValue = @"Mermaid Source";
        self.editorPaneSubtitleLabel.stringValue = @"Editor with live highlighting and parser feedback";
        [self mountEditorPaneBodyView:self.editorScrollView];
        self.commandField.hidden = NO;
        self.commandButton.hidden = NO;
        self.contextLabel.hidden = NO;
        self.mermaidModeMenuItem.state = NSControlStateValueOn;
        self.freeformModeMenuItem.state = NSControlStateValueOff;
        [self.window makeFirstResponder:self.editorTextView];
    }
}

- (void)refreshFreeformCanvasFromEditorSource {
    NSString *source = self.editorTextView.string ?: @"";
    const char *sourceUTF8 = source.UTF8String ?: "";
    char message[256] = {0};
    const MerrowFreeformGraphSnapshot *graph = merrow_studio_build_editable_graph((const uint8_t *)sourceUTF8,
                                                                                  (uint32_t)strlen(sourceUTF8),
                                                                                  message,
                                                                                  sizeof(message));
    if (!graph) {
        [self.freeformCanvasComponent clearDocument];
        self.freeformSelectionLabel.stringValue = @"No selection";
        [self syncFreeformInspectorControls];
        self.statusLabel.stringValue = [NSString stringWithUTF8String:message[0] != 0 ? message : "Freeform canvas unavailable"]; 
        return;
    }

    [self.freeformCanvasComponent loadEditableGraph:graph];
    merrow_studio_free_editable_graph(graph);
    [self syncFreeformInspectorControls];
    self.statusLabel.stringValue = [NSString stringWithUTF8String:message[0] != 0 ? message : "Editable canvas ready"];
}

- (IBAction)selectEditingMode:(id)sender {
    NSString *mode = [sender representedObject];
    BOOL shouldUseFreeform = [mode isEqualToString:@"freeform"];
    if (self.freeformModeEnabled == shouldUseFreeform) {
        [self applyEditingModeUI];
        return;
    }

    self.freeformModeEnabled = shouldUseFreeform;
    [self applyEditingModeUI];
    if (self.freeformModeEnabled) {
        if (self.currentDocumentIsFreeform) {
            [self syncFreeformInspectorControls];
            self.statusLabel.stringValue = @"Freeform canvas mode enabled for current FFM document.";
        } else {
            [self refreshFreeformCanvasFromEditorSource];
        }
    } else {
        self.statusLabel.stringValue = self.currentDocumentIsFreeform ? @"Mermaid source mode enabled for current FFM document." : @"Mermaid source mode enabled.";
    }
}

- (IBAction)resetFreeformToMermaid:(id)sender {
    (void)sender;

    NSString *source = self.editorTextView.string ?: @"";
    const char *sourceUTF8 = source.UTF8String ?: "";
    char message[256] = {0};
    const MerrowFreeformGraphSnapshot *graph = merrow_studio_build_editable_graph((const uint8_t *)sourceUTF8,
                                                                                  (uint32_t)strlen(sourceUTF8),
                                                                                  message,
                                                                                  sizeof(message));
    if (!graph) {
        self.statusLabel.stringValue = [NSString stringWithUTF8String:message[0] != 0 ? message : "Unable to reset freeform canvas from Mermaid source."];
        return;
    }

    [self.freeformCanvasComponent loadEditableGraph:graph];
    merrow_studio_free_editable_graph(graph);

    if (!self.freeformModeEnabled) {
        self.freeformModeEnabled = YES;
        [self applyEditingModeUI];
    }

    [self syncFreeformInspectorControls];
    [self markDocumentEdited:YES];
    self.statusLabel.stringValue = @"Freeform canvas reset from Mermaid source.";
}

- (uint32_t)selectedFreeformShapeCode {
    NSNumber *shapeValue = [self.freeformShapePopup.selectedItem.representedObject isKindOfClass:[NSNumber class]] ? self.freeformShapePopup.selectedItem.representedObject : @1;
    return (uint32_t)shapeValue.unsignedIntValue;
}

- (IBAction)beginFreeformAddShape:(id)sender {
    (void)sender;
    [self.freeformCanvasComponent beginInsertingNodeWithShape:[self selectedFreeformShapeCode]];
    [self clearFreeformInspectorModeOverride];
    [self syncFreeformInspectorControls];
    self.statusLabel.stringValue = self.freeformCanvasComponent.insertionSummary ?: @"Click the canvas to place the new shape.";
    [self.window makeFirstResponder:self.freeformCanvasComponent];
}

- (IBAction)showFreeformAddObjectMode:(id)sender {
    (void)sender;
    [self setFreeformInspectorModeOverride:MerrowFreeformInspectorModeAddObject];
    [self syncFreeformInspectorControls];
    self.statusLabel.stringValue = @"Add Object mode ready.";
    [self.window makeFirstResponder:self.freeformCanvasComponent];
}

- (IBAction)showFreeformAddLinkMode:(id)sender {
    (void)sender;
    [self setFreeformInspectorModeOverride:MerrowFreeformInspectorModeAddLink];
    [self syncFreeformInspectorControls];
    self.statusLabel.stringValue = @"Add Link mode ready.";
    [self.window makeFirstResponder:self.freeformCanvasComponent];
}

- (IBAction)beginFreeformAddShapeFromMenu:(id)sender {
    NSNumber *shapeValue = [sender representedObject];
    if ([shapeValue isKindOfClass:[NSNumber class]]) {
        for (NSMenuItem *item in self.freeformShapePopup.itemArray) {
            if ([item.representedObject isKindOfClass:[NSNumber class]] && [item.representedObject isEqualToNumber:shapeValue]) {
                [self.freeformShapePopup selectItem:item];
                break;
            }
        }
    }
    [self beginFreeformAddShape:nil];
}

- (IBAction)beginFreeformAddGroup:(id)sender {
    (void)sender;
    [self.freeformCanvasComponent beginInsertingSubgraph];
    [self clearFreeformInspectorModeOverride];
    [self syncFreeformInspectorControls];
    self.statusLabel.stringValue = self.freeformCanvasComponent.insertionSummary ?: @"Click the canvas to place the new group.";
    [self.window makeFirstResponder:self.freeformCanvasComponent];
}

- (IBAction)cancelFreeformInsertion:(id)sender {
    (void)sender;
    [self.freeformCanvasComponent cancelInsertionMode];
    [self clearFreeformInspectorModeOverride];
    [self syncFreeformInspectorControls];
    self.statusLabel.stringValue = @"Freeform insertion cancelled.";
}

- (IBAction)applyFreeformSelectedShape:(id)sender {
    (void)sender;
    if (!self.freeformCanvasComponent.hasSelectedNode) {
        return;
    }
    [self.freeformCanvasComponent updateSelectedNodeShape:[self selectedFreeformShapeCode]];
    [self syncFreeformInspectorControls];
    [self markDocumentEdited:YES];
    self.statusLabel.stringValue = @"Shape updated.";
}

- (IBAction)addFreeformConnector:(id)sender {
    (void)sender;
    NSString *sourceId = [self selectedObjectIdForPopup:self.freeformConnectorSourcePopup];
    NSString *targetId = [self selectedObjectIdForPopup:self.freeformConnectorTargetPopup];
    if (![self.freeformCanvasComponent createConnectorFromObjectId:sourceId toObjectId:targetId]) {
        self.statusLabel.stringValue = @"Choose two different shapes or groups to create a connector.";
        return;
    }
    self.statusLabel.stringValue = @"Connector added.";
}

- (IBAction)applyFreeformNodeLabel:(id)sender {
    (void)sender;
    [self.freeformCanvasComponent updateSelectedNodeLabel:self.freeformNodeLabelField.stringValue ?: @""];
    [self markDocumentEdited:YES];
}

- (IBAction)applyFreeformCanvasBackgroundColor:(id)sender {
    (void)sender;
    [self.freeformCanvasComponent updateCanvasBackgroundColor:self.freeformCanvasBackgroundColorWell.color];
    [self syncFreeformInspectorControls];
    [self markDocumentEdited:YES];
}

- (IBAction)applyFreeformCanvasBackgroundOpacity:(id)sender {
    (void)sender;
    [self.freeformCanvasComponent updateCanvasBackgroundOpacity:self.freeformCanvasBackgroundOpacitySlider.doubleValue];
    [self syncFreeformInspectorControls];
    [self markDocumentEdited:YES];
}

- (IBAction)applyFreeformDefaultNodeFillColor:(id)sender {
    (void)sender;
    [self.freeformCanvasComponent updateDefaultNodeFillColor:self.freeformDefaultNodeFillColorWell.color];
    [self syncFreeformInspectorControls];
    [self markDocumentEdited:YES];
}

- (IBAction)applyFreeformDefaultNodeStrokeColor:(id)sender {
    (void)sender;
    [self.freeformCanvasComponent updateDefaultNodeStrokeColor:self.freeformDefaultNodeStrokeColorWell.color];
    [self syncFreeformInspectorControls];
    [self markDocumentEdited:YES];
}

- (IBAction)applyFreeformDefaultNodeStrokeWidth:(id)sender {
    (void)sender;
    [self.freeformCanvasComponent updateDefaultNodeStrokeWidth:self.freeformDefaultNodeStrokeWidthSlider.doubleValue];
    [self syncFreeformInspectorControls];
    [self markDocumentEdited:YES];
}

- (IBAction)applyFreeformDefaultSubgraphFillColor:(id)sender {
    (void)sender;
    [self.freeformCanvasComponent updateDefaultSubgraphFillColor:self.freeformDefaultSubgraphFillColorWell.color];
    [self syncFreeformInspectorControls];
    [self markDocumentEdited:YES];
}

- (IBAction)applyFreeformDefaultSubgraphStrokeColor:(id)sender {
    (void)sender;
    [self.freeformCanvasComponent updateDefaultSubgraphStrokeColor:self.freeformDefaultSubgraphStrokeColorWell.color];
    [self syncFreeformInspectorControls];
    [self markDocumentEdited:YES];
}

- (IBAction)applyFreeformDefaultSubgraphStrokeWidth:(id)sender {
    (void)sender;
    [self.freeformCanvasComponent updateDefaultSubgraphStrokeWidth:self.freeformDefaultSubgraphStrokeWidthSlider.doubleValue];
    [self syncFreeformInspectorControls];
    [self markDocumentEdited:YES];
}

- (IBAction)applyFreeformDefaultEdgeColor:(id)sender {
    (void)sender;
    [self.freeformCanvasComponent updateDefaultEdgeStrokeColor:self.freeformDefaultEdgeColorWell.color];
    [self syncFreeformInspectorControls];
    [self markDocumentEdited:YES];
}

- (IBAction)applyFreeformDefaultEdgeThickness:(id)sender {
    (void)sender;
    [self.freeformCanvasComponent updateDefaultEdgeThickness:self.freeformDefaultEdgeThicknessSlider.doubleValue];
    [self syncFreeformInspectorControls];
    [self markDocumentEdited:YES];
}

- (IBAction)applyFreeformDefaultEdgePattern:(id)sender {
    (void)sender;
    [self.freeformCanvasComponent updateDefaultEdgeLineStyle:self.freeformDefaultEdgePatternPopup.indexOfSelectedItem];
    [self syncFreeformInspectorControls];
    [self markDocumentEdited:YES];
}

- (IBAction)applyFreeformDefaultEdgeArrowMode:(id)sender {
    (void)sender;
    [self.freeformCanvasComponent updateDefaultEdgeArrowMode:self.freeformDefaultEdgeArrowPopup.indexOfSelectedItem];
    [self syncFreeformInspectorControls];
    [self markDocumentEdited:YES];
}

- (IBAction)applyFreeformObjectWidth:(id)sender {
    (void)sender;
    [self.freeformCanvasComponent updateSelectedObjectWidth:MAX(1.0, self.freeformWidthField.doubleValue)];
    [self markDocumentEdited:YES];
}

- (IBAction)applyFreeformObjectHeight:(id)sender {
    (void)sender;
    [self.freeformCanvasComponent updateSelectedObjectHeight:MAX(1.0, self.freeformHeightField.doubleValue)];
    [self markDocumentEdited:YES];
}

- (IBAction)applyFreeformFillColor:(id)sender {
    (void)sender;
    [self.freeformCanvasComponent updateSelectedNodeFillColor:self.freeformFillColorWell.color];
    [self markDocumentEdited:YES];
}

- (IBAction)applyFreeformStrokeColor:(id)sender {
    (void)sender;
    [self.freeformCanvasComponent updateSelectedNodeStrokeColor:self.freeformStrokeColorWell.color];
    [self markDocumentEdited:YES];
}

- (IBAction)applyFreeformStrokeWidth:(id)sender {
    (void)sender;
    [self.freeformCanvasComponent updateSelectedNodeStrokeWidth:self.freeformStrokeWidthSlider.doubleValue];
    [self markDocumentEdited:YES];
}

- (IBAction)applyFreeformEdgeLabel:(id)sender {
    (void)sender;
    [self.freeformCanvasComponent updateSelectedEdgeLabel:self.freeformEdgeLabelField.stringValue ?: @""];
    [self markDocumentEdited:YES];
}

- (IBAction)applyFreeformEdgeColor:(id)sender {
    (void)sender;
    [self.freeformCanvasComponent updateSelectedEdgeStrokeColor:self.freeformEdgeColorWell.color];
    [self markDocumentEdited:YES];
}

- (IBAction)applyFreeformEdgeThickness:(id)sender {
    (void)sender;
    [self.freeformCanvasComponent updateSelectedEdgeThickness:self.freeformEdgeThicknessSlider.doubleValue];
    [self markDocumentEdited:YES];
}

- (IBAction)applyFreeformEdgePattern:(id)sender {
    (void)sender;
    [self.freeformCanvasComponent updateSelectedEdgeLineStyle:self.freeformEdgePatternPopup.indexOfSelectedItem];
    [self markDocumentEdited:YES];
}

- (IBAction)applyFreeformEdgeArrowMode:(id)sender {
    (void)sender;
    [self.freeformCanvasComponent updateSelectedEdgeArrowMode:self.freeformEdgeArrowPopup.indexOfSelectedItem];
    [self markDocumentEdited:YES];
}

- (void)freeformCanvasComponentDidChangeSelection:(MerrowFreeformCanvasComponent *)component {
    [self clearFreeformInspectorModeOverride];
    self.freeformSelectionLabel.stringValue = component.selectionSummary ?: @"No selection";
    [self syncFreeformInspectorControls];
}

- (void)freeformCanvasComponentDidMutateDocument:(MerrowFreeformCanvasComponent *)component {
    (void)component;
    self.freeformSelectionLabel.stringValue = self.freeformCanvasComponent.selectionSummary ?: @"No selection";
    [self syncFreeformInspectorControls];
    [self markDocumentEdited:YES];
    self.statusLabel.stringValue = @"Freeform canvas updated.";
}

- (void)applyDiagramCommandText:(NSString *)command clearCommandField:(BOOL)clearCommandField {
    NSString *trimmedCommand = [command stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (trimmedCommand.length == 0) {
        self.statusLabel.stringValue = @"Enter a diagram command first.";
        return;
    }

    const NSUInteger generation = self.editorGeneration;
    NSString *source = [self.editorTextView.string copy] ?: @"";

    dispatch_async(self.editorWorkQueue, ^{
        @autoreleasepool {
            const char *source_utf8 = source.UTF8String ?: "";
            const char *command_utf8 = trimmedCommand.UTF8String ?: "";
            const char *context_utf8 = self.currentCommandContextId.UTF8String ?: "";
            char commandMessage[256] = {0};
            char contextId[256] = {0};
            char contextDisplay[256] = {0};
            char *editedSource = merrow_studio_apply_command((const uint8_t *)source_utf8,
                                                             (uint32_t)strlen(source_utf8),
                                                             (const uint8_t *)command_utf8,
                                                             (uint32_t)strlen(command_utf8),
                                                             (const uint8_t *)context_utf8,
                                                             (uint32_t)strlen(context_utf8),
                                                             contextId,
                                                             sizeof(contextId),
                                                             contextDisplay,
                                                             sizeof(contextDisplay),
                                                             commandMessage,
                                                             sizeof(commandMessage));

            const char *messageBytes = commandMessage[0] != 0 ? commandMessage : (editedSource ? "Command applied" : "Command failed");
            NSString *message = [[NSString alloc] initWithBytes:messageBytes
                                                         length:strlen(messageBytes)
                                                       encoding:NSUTF8StringEncoding] ?: @"Command failed";
            NSString *updatedSource = nil;
            NSString *updatedContextId = nil;
            NSString *updatedContextDisplay = nil;
            if (editedSource) {
                updatedSource = [[NSString alloc] initWithBytes:editedSource
                                                         length:strlen(editedSource)
                                                       encoding:NSUTF8StringEncoding];
            }
            if (contextId[0] != 0) {
                updatedContextId = [[NSString alloc] initWithBytes:contextId
                                                            length:strlen(contextId)
                                                          encoding:NSUTF8StringEncoding] ?: @"";
            }
            if (contextDisplay[0] != 0) {
                updatedContextDisplay = [[NSString alloc] initWithBytes:contextDisplay
                                                                 length:strlen(contextDisplay)
                                                               encoding:NSUTF8StringEncoding] ?: @"";
            }
            if (editedSource) {
                merrow_studio_free_string(editedSource);
            }

            dispatch_async(dispatch_get_main_queue(), ^{
                if (generation != self.editorGeneration) {
                    self.statusLabel.stringValue = @"Command cancelled because the document changed.";
                    return;
                }

                if (updatedSource) {
                    [self replaceEditorSourceFromCommand:updatedSource status:message contextId:updatedContextId contextDisplay:updatedContextDisplay];
                    if (clearCommandField) {
                        self.commandField.stringValue = @"";
                    }
                    [self.window makeFirstResponder:self.editorTextView];
                } else {
                    self.statusLabel.stringValue = message ?: @"Command failed";
                    [self.window makeFirstResponder:clearCommandField ? self.commandField : self.editorTextView];
                }
            });
        }
    });
}

- (IBAction)runDiagramCommand:(id)sender {
    (void)sender;
    NSString *command = [self.commandField.stringValue stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    [self applyDiagramCommandText:command clearCommandField:YES];
}

- (IBAction)selectDiagramDirection:(id)sender {
    NSString *direction = [sender representedObject];
    if (direction.length == 0) {
        self.statusLabel.stringValue = @"Direction menu item is misconfigured.";
        return;
    }

    [self applyDiagramCommandText:[NSString stringWithFormat:@"direction %@", direction] clearCommandField:NO];
}

- (IBAction)shuffleDiagramLayout:(id)sender {
    (void)sender;

    const NSUInteger generation = self.editorGeneration;
    NSString *source = [self.editorTextView.string copy] ?: @"";

    dispatch_async(self.editorWorkQueue, ^{
        @autoreleasepool {
            const char *source_utf8 = source.UTF8String ?: "";
            char shuffleMessage[256] = {0};
            char *editedSource = merrow_studio_shuffle_diagram((const uint8_t *)source_utf8,
                                                               (uint32_t)strlen(source_utf8),
                                                               shuffleMessage,
                                                               sizeof(shuffleMessage));

            const char *messageBytes = shuffleMessage[0] != 0 ? shuffleMessage : (editedSource ? "Shuffle applied" : "Shuffle unavailable");
            NSString *message = [[NSString alloc] initWithBytes:messageBytes
                                                         length:strlen(messageBytes)
                                                       encoding:NSUTF8StringEncoding] ?: @"Shuffle unavailable";
            NSString *updatedSource = nil;
            if (editedSource) {
                updatedSource = [[NSString alloc] initWithBytes:editedSource
                                                         length:strlen(editedSource)
                                                       encoding:NSUTF8StringEncoding];
                merrow_studio_free_string(editedSource);
            }

            dispatch_async(dispatch_get_main_queue(), ^{
                if (generation != self.editorGeneration) {
                    self.statusLabel.stringValue = @"Shuffle cancelled because the document changed.";
                    return;
                }

                if (updatedSource) {
                    [self replaceEditorSourceFromCommand:updatedSource status:message contextId:nil contextDisplay:nil];
                    [self.window makeFirstResponder:self.editorTextView];
                } else {
                    self.statusLabel.stringValue = message;
                }
            });
        }
    });
}

- (void)processEditorChange {
    if (!self.editorTextView) return;

    const NSUInteger generation = self.editorGeneration;
    NSString *source = [self.editorTextView.string copy] ?: @"";
    NSString *fileName = self.currentSourcePath.lastPathComponent ?: @"untitled.mmd";

    dispatch_async(self.editorWorkQueue, ^{
        @autoreleasepool {
            const char *utf8 = source.UTF8String ?: "";
            char syntaxMessage[256] = {0};
            int syntaxResult = merrow_studio_check_mermaid_syntax((const uint8_t *)utf8, (uint32_t)strlen(utf8), syntaxMessage, sizeof(syntaxMessage));

            NSString *syntaxString = [NSString stringWithUTF8String:syntaxMessage[0] != 0 ? syntaxMessage : "Syntax check failed"];
            const MerrowStudioScene *scene = NULL;
            char previewPath[4096] = {0};
            char previewMessage[256] = {0};
            int previewResult = 2;

            if (syntaxResult == 0) {
                scene = merrow_studio_build_scene((const uint8_t *)utf8, (uint32_t)strlen(utf8));
                if (!scene) {
                    previewResult = merrow_studio_render_preview_png((const uint8_t *)utf8, (uint32_t)strlen(utf8), previewPath, sizeof(previewPath), previewMessage, sizeof(previewMessage));
                }
            }

            NSString *previewPathString = previewPath[0] != 0 ? [NSString stringWithUTF8String:previewPath] : nil;

            dispatch_async(dispatch_get_main_queue(), ^{
                if (generation != self.editorGeneration) {
                    if (scene) merrow_studio_free_scene(scene);
                    if (previewPathString.length > 0) {
                        [[NSFileManager defaultManager] removeItemAtPath:previewPathString error:nil];
                    }
                    return;
                }

                self.statusLabel.stringValue = [NSString stringWithFormat:@"%@ | %@", syntaxString, fileName];

                if (scene) {
                    [self.viewerRenderer replaceScene:scene];
                    [self.viewerView setNeedsDisplay:YES];
                } else if (previewResult == 0 && previewPathString.length > 0) {
                    NSImage *image = [[NSImage alloc] initWithContentsOfFile:previewPathString];
                    if (image) {
                        [self.viewerRenderer replacePreviewImage:image path:previewPathString];
                        [self.viewerView setNeedsDisplay:YES];
                    } else {
                        [[NSFileManager defaultManager] removeItemAtPath:previewPathString error:nil];
                    }
                }
            });
        }
    });
}

- (NSString *)editorDisplayName {
    return self.currentSourcePath.lastPathComponent ?: @"untitled.mmd";
}

- (NSString *)exportBaseName {
    NSString *displayName = [self editorDisplayName];
    NSString *stem = displayName.stringByDeletingPathExtension;
    return stem.length > 0 ? stem : @"diagram";
}

- (NSString *)ensurePath:(NSString *)path hasExtension:(NSString *)fileExtension {
    if (path.pathExtension.length > 0) {
        return path;
    }
    return [path stringByAppendingPathExtension:fileExtension] ?: path;
}

- (NSView *)exportAccessoryViewWithLabel:(NSString *)labelText popup:(NSPopUpButton **)outPopup options:(NSArray<NSString *> *)options {
    NSView *container = [[NSView alloc] initWithFrame:NSMakeRect(0.0, 0.0, 320.0, 32.0)];

    NSTextField *label = [NSTextField labelWithString:labelText];
    label.frame = NSMakeRect(0.0, 7.0, 80.0, 18.0);
    [container addSubview:label];

    NSPopUpButton *popup = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(92.0, 2.0, 220.0, 26.0) pullsDown:NO];
    [popup addItemsWithTitles:options];
    [popup selectItemAtIndex:0];
    [container addSubview:popup];

    if (outPopup) {
        *outPopup = popup;
    }

    return container;
}

- (void)runExportForFormat:(uint32_t)format
           defaultExtension:(NSString *)fileExtension
                 panelTitle:(NSString *)panelTitle
                optionLabel:(NSString *)optionLabel
               optionTitles:(NSArray<NSString *> *)optionTitles
               rasterScales:(NSArray<NSNumber *> *)rasterScales
               layoutScales:(NSArray<NSNumber *> *)layoutScales {
    NSSavePanel *panel = [NSSavePanel savePanel];
    panel.title = panelTitle;
    panel.canCreateDirectories = YES;
    MerrowSetAllowedFileTypes(panel, @[ fileExtension ]);
    panel.nameFieldStringValue = [NSString stringWithFormat:@"%@.%@", [self exportBaseName], fileExtension];

    NSString *directory = self.currentSourcePath.stringByDeletingLastPathComponent;
    if (directory.length > 0) {
        panel.directoryURL = [NSURL fileURLWithPath:directory];
    }

    NSPopUpButton *popup = nil;
    panel.accessoryView = [self exportAccessoryViewWithLabel:optionLabel popup:&popup options:optionTitles];

    [panel beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse response) {
        if (response != NSModalResponseOK || panel.URL.path.length == 0) {
            return;
        }

        NSInteger selectedIndex = popup.indexOfSelectedItem;
        if (selectedIndex < 0 || selectedIndex >= (NSInteger)MIN(rasterScales.count, layoutScales.count)) {
            selectedIndex = 0;
        }

        NSString *exportPath = [self ensurePath:panel.URL.path hasExtension:fileExtension];
        const double rasterScale = rasterScales[(NSUInteger)selectedIndex].doubleValue;
        const double layoutScale = layoutScales[(NSUInteger)selectedIndex].doubleValue;
        if (self.currentDocumentIsFreeform || self.freeformModeEnabled) {
            NSError *error = nil;
            BOOL ok = NO;
            if (format == 0) {
                ok = [self.freeformCanvasComponent writePNGExportToPath:exportPath scale:rasterScale error:&error];
            } else {
                ok = [self.freeformCanvasComponent writeSVGExportToPath:exportPath scale:layoutScale error:&error];
            }
            if (ok) {
                NSString *kind = format == 0 ? @"Freeform PNG exported" : @"Freeform SVG exported";
                self.statusLabel.stringValue = [NSString stringWithFormat:@"%@: %@", kind, exportPath.lastPathComponent ?: exportPath];
            } else {
                self.statusLabel.stringValue = [NSString stringWithFormat:@"Export failed: %@", error.localizedDescription ?: @"unknown error"];
            }
        } else {
            NSString *source = self.editorTextView.string ?: @"";
            const char *utf8 = source.UTF8String ?: "";
            char exportMessage[256] = {0};
            const int exportResult = merrow_studio_export_diagram((const uint8_t *)utf8,
                                                                  (uint32_t)strlen(utf8),
                                                                  exportPath.UTF8String,
                                                                  format,
                                                                  rasterScale,
                                                                  layoutScale,
                                                                  exportMessage,
                                                                  sizeof(exportMessage));

            NSString *message = [NSString stringWithUTF8String:exportMessage[0] != 0 ? exportMessage : "Export finished"];
            if (exportResult == 0) {
                self.statusLabel.stringValue = [NSString stringWithFormat:@"%@: %@", message, exportPath.lastPathComponent ?: exportPath];
            } else {
                self.statusLabel.stringValue = [NSString stringWithFormat:@"Export failed: %@", message];
            }
        }
    }];
}

- (void)updateWindowTitle {
    if (!self.window) return;

    NSString *displayName = [self editorDisplayName];
    self.window.title = [NSString stringWithFormat:@"%@ - Merrow Studio", displayName];
    self.window.representedURL = self.currentSourcePath != nil ? [NSURL fileURLWithPath:self.currentSourcePath] : nil;
}

- (void)markDocumentEdited:(BOOL)edited {
    [self.window setDocumentEdited:edited];
    [self updateWindowTitle];
}

- (void)applyEditorSource:(NSString *)source fromPath:(NSString *)sourcePath {
    self.isSynchronizingEditor = YES;
    self.currentSourcePath = [sourcePath copy];
    self.currentDocumentIsFreeform = sourcePath.length > 0 && [self isFreeformGraphPath:sourcePath];
    [self.editorTextView setString:source ?: @""];
    [self applySyntaxHighlighting];
    self.editorGeneration += 1;
    [self requestEditorAnalysis];
    [self.editorTextView setSelectedRange:NSMakeRange(0, 0)];
    [self.editorTextView scrollRangeToVisible:NSMakeRange(0, 0)];
    self.isSynchronizingEditor = NO;
    [self clearCommandContext];
    [self markDocumentEdited:NO];
}

- (BOOL)writeEditorSourceToPath:(NSString *)targetPath error:(NSError **)error {
    if (targetPath.length == 0) {
        if (error) {
            *error = [NSError errorWithDomain:NSCocoaErrorDomain code:NSFileNoSuchFileError userInfo:@{ NSLocalizedDescriptionKey: @"No target file path was provided." }];
        }
        return NO;
    }

    NSString *source = self.editorTextView.string ?: @"";
    BOOL ok = [source writeToFile:targetPath atomically:YES encoding:NSUTF8StringEncoding error:error];
    if (ok) {
        self.currentSourcePath = [targetPath copy];
        [self markDocumentEdited:NO];
        self.statusLabel.stringValue = [NSString stringWithFormat:@"Saved %@", self.currentSourcePath.lastPathComponent ?: @"document"];
    }
    return ok;
}

- (BOOL)writeCurrentDocumentToPath:(NSString *)targetPath error:(NSError **)error {
    if (self.freeformModeEnabled || [self isFreeformGraphPath:targetPath] || self.currentDocumentIsFreeform) {
        return [self writeFreeformDocumentToPath:targetPath error:error];
    }
    return [self writeEditorSourceToPath:targetPath error:error];
}

- (void)runSavePanelForPath:(NSString *)suggestedPath completion:(void (^)(BOOL saved))completion {
    NSSavePanel *panel = [NSSavePanel savePanel];
    panel.canCreateDirectories = YES;
    const BOOL savingFreeformDocument = self.freeformModeEnabled || self.currentDocumentIsFreeform;
    MerrowSetAllowedFileTypes(panel, savingFreeformDocument ? @[ @"ffm" ] : @[ @"mmd", @"mermaid", @"txt" ]);
    panel.nameFieldStringValue = suggestedPath.lastPathComponent ?: [self editorDisplayName];
    if (suggestedPath.stringByDeletingLastPathComponent.length > 0) {
        panel.directoryURL = [NSURL fileURLWithPath:suggestedPath.stringByDeletingLastPathComponent];
    }

    [panel beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse response) {
        if (response != NSModalResponseOK || panel.URL.path.length == 0) {
            if (completion) completion(NO);
            return;
        }

        NSError *error = nil;
        BOOL saved = [self writeCurrentDocumentToPath:panel.URL.path error:&error];
        if (!saved) {
            self.statusLabel.stringValue = [NSString stringWithFormat:@"Save failed: %@", error.localizedDescription ?: @"unknown error"];
        }
        if (completion) completion(saved);
    }];
}

- (void)performSaveWithSaveAs:(BOOL)saveAs completion:(void (^)(BOOL saved))completion {
    if (!saveAs && self.currentSourcePath.length > 0) {
        NSError *error = nil;
        BOOL saved = [self writeCurrentDocumentToPath:self.currentSourcePath error:&error];
        if (!saved) {
            self.statusLabel.stringValue = [NSString stringWithFormat:@"Save failed: %@", error.localizedDescription ?: @"unknown error"];
        }
        if (completion) completion(saved);
        return;
    }

    NSString *suggestedPath = self.currentSourcePath;
    if (suggestedPath.length == 0) {
        const BOOL savingFreeformDocument = self.freeformModeEnabled || self.currentDocumentIsFreeform;
        suggestedPath = [NSTemporaryDirectory() stringByAppendingPathComponent:(savingFreeformDocument ? @"untitled.ffm" : [self editorDisplayName])];
    }
    [self runSavePanelForPath:suggestedPath completion:completion];
}

- (void)promptToSaveIfNeededThen:(void (^)(BOOL shouldContinue))completion {
    if (!self.window.documentEdited) {
        if (completion) completion(YES);
        return;
    }

    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = [NSString stringWithFormat:@"Save changes to %@?", [self editorDisplayName]];
    alert.informativeText = @"Your Mermaid source has unsaved changes.";
    [alert addButtonWithTitle:@"Save"];
    [alert addButtonWithTitle:@"Don't Save"];
    [alert addButtonWithTitle:@"Cancel"];

    [alert beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse response) {
        if (response == NSAlertFirstButtonReturn) {
            [self performSaveWithSaveAs:NO completion:^(BOOL saved) {
                if (completion) completion(saved);
            }];
            return;
        }

        if (response == NSAlertSecondButtonReturn) {
            if (completion) completion(YES);
            return;
        }

        if (completion) completion(NO);
    }];
}

- (void)loadEditorSourceFromPath:(NSString *)sourcePath {
    if ([self isFreeformGraphPath:sourcePath]) {
        [self loadFreeformDocumentFromPath:sourcePath];
        return;
    }

    [self resetAppStateForIncomingDocument];
    [self blankMermaidWorkspaceForIncomingLoad];

    NSError *error = nil;
    NSString *source = [NSString stringWithContentsOfFile:sourcePath encoding:NSUTF8StringEncoding error:&error];
    if (!source) {
        self.statusLabel.stringValue = [NSString stringWithFormat:@"Failed to load source: %@", error.localizedDescription ?: @"unknown error"];
        return;
    }

    [self finishLoadingMermaidSource:source fromPath:sourcePath];
}

- (void)textDidChange:(NSNotification *)notification {
    if (notification.object != self.editorTextView || self.isApplyingHighlighting || self.isSynchronizingEditor) return;
    self.editorGeneration += 1;
    [self clearCommandContext];
    [self markDocumentEdited:YES];
    [self debounceSyntaxHighlighting];
    [self requestEditorAnalysis];
}

- (IBAction)newDocument:(id)sender {
    (void)sender;
    [self promptToSaveIfNeededThen:^(BOOL shouldContinue) {
        if (!shouldContinue) return;
        [self resetAppStateForIncomingDocument];
        [self finishLoadingMermaidSource:MerrowStudioUntitledSource() fromPath:nil];
        self.statusLabel.stringValue = @"New Mermaid document.";
    }];
}

- (IBAction)openDocument:(id)sender {
    (void)sender;
    [self promptToSaveIfNeededThen:^(BOOL shouldContinue) {
        if (!shouldContinue) return;

        NSOpenPanel *panel = [NSOpenPanel openPanel];
        panel.canChooseFiles = YES;
        panel.canChooseDirectories = NO;
        panel.allowsMultipleSelection = NO;
        MerrowSetAllowedFileTypes(panel, @[ @"mmd", @"mermaid", @"txt", @"md", @"ffm", @"merrowgraph" ]);

        [panel beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse response) {
            if (response != NSModalResponseOK || panel.URL.path.length == 0) return;
            [self loadEditorSourceFromPath:panel.URL.path];
        }];
    }];
}

- (IBAction)saveDocument:(id)sender {
    (void)sender;
    [self performSaveWithSaveAs:NO completion:nil];
}

- (IBAction)saveDocumentAs:(id)sender {
    (void)sender;
    [self performSaveWithSaveAs:YES completion:nil];
}

- (IBAction)exportFreeformDocument:(id)sender {
    (void)sender;
    if (!self.freeformModeEnabled && !self.currentDocumentIsFreeform) {
        self.statusLabel.stringValue = @"Switch to Freeform Canvas mode before exporting an FFM document.";
        return;
    }
    [self performSaveWithSaveAs:YES completion:nil];
}

- (IBAction)importFreeformDocument:(id)sender {
    (void)sender;
    [self promptToSaveIfNeededThen:^(BOOL shouldContinue) {
        if (!shouldContinue) return;

        NSOpenPanel *panel = [NSOpenPanel openPanel];
        panel.canChooseFiles = YES;
        panel.canChooseDirectories = NO;
        panel.allowsMultipleSelection = NO;
        MerrowSetAllowedFileTypes(panel, @[ @"ffm", @"merrowgraph" ]);

        [panel beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse response) {
            if (response != NSModalResponseOK || panel.URL.path.length == 0) return;
            [self loadFreeformDocumentFromPath:panel.URL.path];
        }];
    }];
}

- (IBAction)exportDocumentAsPNG:(id)sender {
    (void)sender;
    [self runExportForFormat:0
            defaultExtension:@"png"
                  panelTitle:@"Export Diagram as PNG"
                 optionLabel:@"Quality:"
                optionTitles:@[
                    @"Standard (2x)",
                    @"High (3x)",
                    @"Print (4x)",
                ]
                rasterScales:@[
                    @2.0,
                    @3.0,
                    @4.0,
                ]
                layoutScales:@[
                    @1.0,
                    @1.0,
                    @1.0,
                ]];
}

- (IBAction)exportDocumentAsSVG:(id)sender {
    (void)sender;
    [self runExportForFormat:1
            defaultExtension:@"svg"
                  panelTitle:@"Export Diagram as SVG"
                 optionLabel:@"Scale:"
                optionTitles:@[
                    @"Standard (1x)",
                    @"Large (1.25x)",
                    @"Presentation (1.5x)",
                ]
                rasterScales:@[
                    @1.0,
                    @1.0,
                    @1.0,
                ]
                layoutScales:@[
                    @1.0,
                    @1.25,
                    @1.5,
                ]];
}

- (void)installMenuBar {
    NSMenu *menuBar = [[NSMenu alloc] initWithTitle:@""];

    NSString *appName = [self appDisplayName];

    NSMenuItem *appMenuItem = [[NSMenuItem alloc] initWithTitle:appName action:nil keyEquivalent:@""];
    [menuBar addItem:appMenuItem];

    NSMenuItem *editMenuItem = [[NSMenuItem alloc] initWithTitle:@"Edit" action:nil keyEquivalent:@""];
    [menuBar addItem:editMenuItem];

    NSMenuItem *fileMenuItem = [[NSMenuItem alloc] initWithTitle:@"File" action:nil keyEquivalent:@""];
    [menuBar addItem:fileMenuItem];

    NSMenuItem *diagramMenuItem = [[NSMenuItem alloc] initWithTitle:@"Diagram" action:nil keyEquivalent:@""];
    [menuBar addItem:diagramMenuItem];

    NSMenuItem *freeformMenuItem = [[NSMenuItem alloc] initWithTitle:@"Freeform" action:nil keyEquivalent:@""];
    [menuBar addItem:freeformMenuItem];

        NSMenu *appMenu = [[NSMenu alloc] initWithTitle:appName];
        NSString *aboutTitle = [NSString stringWithFormat:@"About %@", appName];
        NSMenuItem *aboutItem = [[NSMenuItem alloc] initWithTitle:aboutTitle
                                      action:@selector(showAboutDialog:)
                                  keyEquivalent:@""];
        aboutItem.target = self;
        [appMenu addItem:aboutItem];
        [appMenu addItem:[NSMenuItem separatorItem]];

        NSString *quitTitle = [NSString stringWithFormat:@"Quit %@", appName];
    NSMenuItem *quitItem = [[NSMenuItem alloc] initWithTitle:quitTitle
                                                      action:@selector(terminate:)
                                               keyEquivalent:@"q"];
    [appMenu addItem:quitItem];
    [appMenuItem setSubmenu:appMenu];

    NSMenu *editMenu = [[NSMenu alloc] initWithTitle:@"Edit"];

    NSMenuItem *undoItem = [[NSMenuItem alloc] initWithTitle:@"Undo" action:@selector(undo:) keyEquivalent:@"z"];
    [editMenu addItem:undoItem];

    NSMenuItem *redoItem = [[NSMenuItem alloc] initWithTitle:@"Redo" action:@selector(redo:) keyEquivalent:@"Z"];
    [editMenu addItem:redoItem];

    [editMenu addItem:[NSMenuItem separatorItem]];

    NSMenuItem *cutItem = [[NSMenuItem alloc] initWithTitle:@"Cut" action:@selector(cut:) keyEquivalent:@"x"];
    [editMenu addItem:cutItem];

    NSMenuItem *copyItem = [[NSMenuItem alloc] initWithTitle:@"Copy" action:@selector(copy:) keyEquivalent:@"c"];
    [editMenu addItem:copyItem];

    NSMenuItem *pasteItem = [[NSMenuItem alloc] initWithTitle:@"Paste" action:@selector(paste:) keyEquivalent:@"v"];
    [editMenu addItem:pasteItem];
    [editMenuItem setSubmenu:editMenu];

    NSMenu *fileMenu = [[NSMenu alloc] initWithTitle:@"File"];

    NSMenuItem *newItem = [[NSMenuItem alloc] initWithTitle:@"New" action:@selector(newDocument:) keyEquivalent:@"n"];
    newItem.target = self;
    [fileMenu addItem:newItem];

    NSMenuItem *openItem = [[NSMenuItem alloc] initWithTitle:@"Open..." action:@selector(openDocument:) keyEquivalent:@"o"];
    openItem.target = self;
    [fileMenu addItem:openItem];

    [fileMenu addItem:[NSMenuItem separatorItem]];

    NSMenuItem *saveItem = [[NSMenuItem alloc] initWithTitle:@"Save" action:@selector(saveDocument:) keyEquivalent:@"s"];
    saveItem.target = self;
    [fileMenu addItem:saveItem];

    NSMenuItem *saveAsItem = [[NSMenuItem alloc] initWithTitle:@"Save As..." action:@selector(saveDocumentAs:) keyEquivalent:@"S"];
    saveAsItem.target = self;
    [fileMenu addItem:saveAsItem];

    [fileMenu addItem:[NSMenuItem separatorItem]];

    NSMenuItem *importFFMItem = [[NSMenuItem alloc] initWithTitle:@"Import Freeform..." action:@selector(importFreeformDocument:) keyEquivalent:@""];
    importFFMItem.target = self;
    [fileMenu addItem:importFFMItem];

    NSMenuItem *exportFFMItem = [[NSMenuItem alloc] initWithTitle:@"Export Freeform..." action:@selector(exportFreeformDocument:) keyEquivalent:@""];
    exportFFMItem.target = self;
    [fileMenu addItem:exportFFMItem];

    [fileMenu addItem:[NSMenuItem separatorItem]];

    NSMenuItem *exportPNGItem = [[NSMenuItem alloc] initWithTitle:@"Export as PNG..." action:@selector(exportDocumentAsPNG:) keyEquivalent:@""];
    exportPNGItem.target = self;
    [fileMenu addItem:exportPNGItem];

    NSMenuItem *exportSVGItem = [[NSMenuItem alloc] initWithTitle:@"Export as SVG..." action:@selector(exportDocumentAsSVG:) keyEquivalent:@""];
    exportSVGItem.target = self;
    [fileMenu addItem:exportSVGItem];

    [fileMenuItem setSubmenu:fileMenu];

    NSMenu *diagramMenu = [[NSMenu alloc] initWithTitle:@"Diagram"];
    NSMenuItem *modeMenuItem = [[NSMenuItem alloc] initWithTitle:@"Mode" action:nil keyEquivalent:@""];
    NSMenu *modeMenu = [[NSMenu alloc] initWithTitle:@"Mode"];

    self.mermaidModeMenuItem = [[NSMenuItem alloc] initWithTitle:@"Mermaid Source" action:@selector(selectEditingMode:) keyEquivalent:@""];
    self.mermaidModeMenuItem.target = self;
    self.mermaidModeMenuItem.representedObject = @"mermaid";
    [modeMenu addItem:self.mermaidModeMenuItem];

    self.freeformModeMenuItem = [[NSMenuItem alloc] initWithTitle:@"Freeform Canvas" action:@selector(selectEditingMode:) keyEquivalent:@""];
    self.freeformModeMenuItem.target = self;
    self.freeformModeMenuItem.representedObject = @"freeform";
    [modeMenu addItem:self.freeformModeMenuItem];

    [modeMenuItem setSubmenu:modeMenu];
    [diagramMenu addItem:modeMenuItem];

    [diagramMenu addItem:[NSMenuItem separatorItem]];

    NSMenuItem *shuffleItem = [[NSMenuItem alloc] initWithTitle:@"Shuffle Layout" action:@selector(shuffleDiagramLayout:) keyEquivalent:@""];
    shuffleItem.target = self;
    [diagramMenu addItem:shuffleItem];

    [diagramMenu addItem:[NSMenuItem separatorItem]];

    NSMenuItem *directionMenuItem = [[NSMenuItem alloc] initWithTitle:@"Direction" action:nil keyEquivalent:@""];
    NSMenu *directionMenu = [[NSMenu alloc] initWithTitle:@"Direction"];

    NSMenuItem *topBottomItem = [[NSMenuItem alloc] initWithTitle:@"Top to Bottom" action:@selector(selectDiagramDirection:) keyEquivalent:@""];
    topBottomItem.target = self;
    topBottomItem.representedObject = @"TB";
    [directionMenu addItem:topBottomItem];

    NSMenuItem *leftRightItem = [[NSMenuItem alloc] initWithTitle:@"Left to Right" action:@selector(selectDiagramDirection:) keyEquivalent:@""];
    leftRightItem.target = self;
    leftRightItem.representedObject = @"LR";
    [directionMenu addItem:leftRightItem];

    NSMenuItem *rightLeftItem = [[NSMenuItem alloc] initWithTitle:@"Right to Left" action:@selector(selectDiagramDirection:) keyEquivalent:@""];
    rightLeftItem.target = self;
    rightLeftItem.representedObject = @"RL";
    [directionMenu addItem:rightLeftItem];

    NSMenuItem *bottomTopItem = [[NSMenuItem alloc] initWithTitle:@"Bottom to Top" action:@selector(selectDiagramDirection:) keyEquivalent:@""];
    bottomTopItem.target = self;
    bottomTopItem.representedObject = @"BT";
    [directionMenu addItem:bottomTopItem];

    [directionMenuItem setSubmenu:directionMenu];
    [diagramMenu addItem:directionMenuItem];

    [diagramMenuItem setSubmenu:diagramMenu];

    NSMenuItem *insertMenuItem = [[NSMenuItem alloc] initWithTitle:@"Insert" action:nil keyEquivalent:@""];
    [menuBar addItem:insertMenuItem];

    NSMenu *insertMenu = [[NSMenu alloc] initWithTitle:@"Insert"];
    self.insertAddObjectMenuItem = [[NSMenuItem alloc] initWithTitle:@"Add Object" action:@selector(showFreeformAddObjectMode:) keyEquivalent:@""];
    self.insertAddObjectMenuItem.target = self;
    [insertMenu addItem:self.insertAddObjectMenuItem];

    self.insertAddLinkMenuItem = [[NSMenuItem alloc] initWithTitle:@"Add Link" action:@selector(showFreeformAddLinkMode:) keyEquivalent:@""];
    self.insertAddLinkMenuItem.target = self;
    [insertMenu addItem:self.insertAddLinkMenuItem];

    [insertMenuItem setSubmenu:insertMenu];

    NSMenu *freeformMenu = [[NSMenu alloc] initWithTitle:@"Freeform"];

    NSMenuItem *insertShapeItem = [[NSMenuItem alloc] initWithTitle:@"Insert Shape" action:nil keyEquivalent:@""];
    self.freeformInsertShapeMenu = [[NSMenu alloc] initWithTitle:@"Insert Shape"];
    [insertShapeItem setSubmenu:self.freeformInsertShapeMenu];
    [freeformMenu addItem:insertShapeItem];

    self.freeformInsertGroupMenuItem = [[NSMenuItem alloc] initWithTitle:@"Insert Group" action:@selector(beginFreeformAddGroup:) keyEquivalent:@""];
    self.freeformInsertGroupMenuItem.target = self;
    [freeformMenu addItem:self.freeformInsertGroupMenuItem];

    [freeformMenu addItem:[NSMenuItem separatorItem]];

    NSMenuItem *resetToMermaidItem = [[NSMenuItem alloc] initWithTitle:@"Reset to Mermaid" action:@selector(resetFreeformToMermaid:) keyEquivalent:@""];
    resetToMermaidItem.target = self;
    [freeformMenu addItem:resetToMermaidItem];

    [freeformMenuItem setSubmenu:freeformMenu];

    [self rebuildFreeformInsertMenu];

    [NSApp setMainMenu:menuBar];
}

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    (void)notification;

    [self installMenuBar];

    NSRect frame = NSMakeRect(0, 0, 1500, 920);
    self.window = [[NSWindow alloc] initWithContentRect:frame
                                              styleMask:NSWindowStyleMaskTitled |
                                                        NSWindowStyleMaskClosable |
                                                        NSWindowStyleMaskResizable |
                                                        NSWindowStyleMaskMiniaturizable
                                                backing:NSBackingStoreBuffered
                                                  defer:NO];
        self.window.delegate = self;
    [self.window center];
    [self.window setTitle:@"Merrow Studio"];
    [self.window makeKeyAndOrderFront:nil];

    if (@available(macOS 11.0, *)) {
        [self.window setToolbarStyle:NSWindowToolbarStyleUnified];
    }

    NSView *contentView = self.window.contentView;
    contentView.wantsLayer = YES;
    contentView.layer.backgroundColor = NSColor.windowBackgroundColor.CGColor;

    NSView *statusBar = [[NSView alloc] initWithFrame:NSZeroRect];
    statusBar.translatesAutoresizingMaskIntoConstraints = NO;
    statusBar.wantsLayer = YES;
    statusBar.layer.backgroundColor = [NSColor colorWithRed:0.93 green:0.94 blue:0.95 alpha:1.0].CGColor;

    self.statusLabel = [NSTextField labelWithString:@"Studio ready."];
    self.statusLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.statusLabel.textColor = [NSColor colorWithRed:0.22 green:0.24 blue:0.28 alpha:1.0];
    self.statusLabel.font = [NSFont systemFontOfSize:12.0 weight:NSFontWeightMedium];
    [statusBar addSubview:self.statusLabel];

    self.contextLabel = [NSTextField labelWithString:@"it=-"];
    self.contextLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.contextLabel.textColor = [NSColor colorWithRed:0.31 green:0.33 blue:0.38 alpha:1.0];
    self.contextLabel.font = [NSFont monospacedSystemFontOfSize:11.0 weight:NSFontWeightRegular];
    self.contextLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    [statusBar addSubview:self.contextLabel];

    self.commandButton = [NSButton buttonWithTitle:@"Apply" target:self action:@selector(runDiagramCommand:)];
    self.commandButton.translatesAutoresizingMaskIntoConstraints = NO;
    self.commandButton.bezelStyle = NSBezelStyleRounded;
    [statusBar addSubview:self.commandButton];

    self.commandField = [[NSTextField alloc] initWithFrame:NSZeroRect];
    self.commandField.translatesAutoresizingMaskIntoConstraints = NO;
    self.commandField.placeholderString = @"Command: connect alpha to beta, delete box alpha, direction LR";
    self.commandField.font = [NSFont systemFontOfSize:12.0 weight:NSFontWeightRegular];
    self.commandField.target = self;
    self.commandField.action = @selector(runDiagramCommand:);
    [statusBar addSubview:self.commandField];

    self.splitView = [[NSSplitView alloc] initWithFrame:NSZeroRect];
    self.splitView.translatesAutoresizingMaskIntoConstraints = NO;
    self.splitView.dividerStyle = NSSplitViewDividerStyleThin;
    self.splitView.vertical = YES;
    self.splitView.wantsLayer = YES;
    self.splitView.delegate = self;
    self.splitView.autosaveName = @"MerrowStudioMainSplit";

    self.editorWorkQueue = dispatch_queue_create("com.merrow.studio.editor-work", DISPATCH_QUEUE_SERIAL);

    MerrowViewportView *viewer = [[MerrowViewportView alloc] initWithFrame:NSZeroRect];
    viewer.translatesAutoresizingMaskIntoConstraints = NO;

    self.viewerRenderer = [[MerrowSceneRenderer alloc] init];
    self.viewerView = viewer;
    viewer.viewportRenderer = self.viewerRenderer;

    NSTextStorage *textStorage = [[NSTextStorage alloc] init];
    NSLayoutManager *layoutManager = [[NSLayoutManager alloc] init];
    layoutManager.allowsNonContiguousLayout = YES;
    [textStorage addLayoutManager:layoutManager];

    NSTextContainer *textContainer = [[NSTextContainer alloc] initWithContainerSize:NSMakeSize(CGFLOAT_MAX, CGFLOAT_MAX)];
    textContainer.widthTracksTextView = YES;
    [layoutManager addTextContainer:textContainer];

    textContainer.heightTracksTextView = NO;

    self.editorTextView = [[MerrowEditorTextView alloc] initWithFrame:NSMakeRect(0.0, 0.0, 640.0, 900.0) textContainer:textContainer];
    self.editorTextView.translatesAutoresizingMaskIntoConstraints = YES;
    self.editorTextView.delegate = self;
    self.editorTextView.editable = YES;
    self.editorTextView.selectable = YES;
    self.editorTextView.richText = NO;
    self.editorTextView.usesFontPanel = NO;
    self.editorTextView.drawsBackground = YES;
    self.editorTextView.automaticQuoteSubstitutionEnabled = NO;
    self.editorTextView.automaticDashSubstitutionEnabled = NO;
    self.editorTextView.automaticTextReplacementEnabled = NO;
    self.editorTextView.automaticSpellingCorrectionEnabled = NO;
    self.editorTextView.automaticDataDetectionEnabled = NO;
    self.editorTextView.allowsUndo = YES;
    self.editorTextView.horizontallyResizable = NO;
    self.editorTextView.verticallyResizable = YES;
    self.editorTextView.minSize = NSMakeSize(0.0, 0.0);
    self.editorTextView.maxSize = NSMakeSize(CGFLOAT_MAX, CGFLOAT_MAX);
    self.editorTextView.autoresizingMask = NSViewWidthSizable;
    self.editorTextView.textContainerInset = NSMakeSize(14.0, 16.0);
    self.editorTextView.backgroundColor = [NSColor colorWithRed:0.10 green:0.11 blue:0.13 alpha:1.0];
    self.editorTextView.insertionPointColor = [NSColor colorWithRed:0.95 green:0.96 blue:0.98 alpha:1.0];
    self.editorTextView.textColor = [NSColor colorWithRed:0.86 green:0.88 blue:0.91 alpha:1.0];
    self.editorTextView.font = [NSFont fontWithName:@"Menlo-Regular" size:14.0] ?: [NSFont monospacedSystemFontOfSize:14.0 weight:NSFontWeightRegular];
    self.editorTextView.typingAttributes = [self baseEditorAttributes];
    self.editorTextView.usesFindBar = YES;
    self.editorTextView.postsFrameChangedNotifications = YES;

    self.editorScrollView = [[NSScrollView alloc] initWithFrame:NSZeroRect];
    self.editorScrollView.translatesAutoresizingMaskIntoConstraints = NO;
    self.editorScrollView.hasVerticalScroller = YES;
    self.editorScrollView.hasHorizontalScroller = NO;
    self.editorScrollView.autohidesScrollers = YES;
    self.editorScrollView.borderType = NSNoBorder;
    self.editorScrollView.backgroundColor = self.editorTextView.backgroundColor;
    self.editorScrollView.documentView = self.editorTextView;
    [self.editorTextView setMinSize:NSMakeSize(0.0, 900.0)];
    [textContainer setContainerSize:NSMakeSize(640.0, CGFLOAT_MAX)];

    char sourcePath[4096] = {0};
    const MerrowStudioScene *defaultScene = merrow_studio_create_default_scene(sourcePath, sizeof(sourcePath));
    if (defaultScene) {
        NSString *sourcePathString = [NSString stringWithUTF8String:sourcePath];
        [self.viewerRenderer replaceScene:defaultScene];
        [self loadEditorSourceFromPath:sourcePathString];
    } else {
        self.statusLabel.stringValue = @"Preview scene creation failed.";
    }
    [viewer setNeedsDisplay:YES];

    self.viewerPaneContentHost = [[NSView alloc] initWithFrame:NSZeroRect];
    self.viewerPaneContentHost.translatesAutoresizingMaskIntoConstraints = NO;
    self.freeformCanvasComponent = [[MerrowFreeformCanvasComponent alloc] initWithFrame:NSZeroRect];
    self.freeformCanvasComponent.translatesAutoresizingMaskIntoConstraints = NO;
    self.freeformCanvasComponent.delegate = self;
    self.viewerPane = [self wrappedPaneWithTitle:@"Diagram View" subtitle:@"Direct AppKit vector preview with pan and zoom" bodyView:self.viewerPaneContentHost dark:NO titleLabel:&_viewerPaneTitleLabel subtitleLabel:&_viewerPaneSubtitleLabel];
    [self mountViewerPaneBodyView:viewer];

    self.editorPaneContentHost = [[NSView alloc] initWithFrame:NSZeroRect];
    self.editorPaneContentHost.translatesAutoresizingMaskIntoConstraints = NO;
    self.freeformToolsScrollView = [self createFreeformToolsScrollView];
    self.editorPane = [self wrappedPaneWithTitle:@"Mermaid Source" subtitle:@"Editor with live highlighting and parser feedback" bodyView:self.editorPaneContentHost dark:YES titleLabel:&_editorPaneTitleLabel subtitleLabel:&_editorPaneSubtitleLabel];
    [self mountEditorPaneBodyView:self.editorScrollView];

    [self.splitView addArrangedSubview:self.viewerPane];
    [self.splitView addArrangedSubview:self.editorPane];
    [self.splitView setHoldingPriority:NSLayoutPriorityDefaultLow forSubviewAtIndex:0];
    [self.splitView setHoldingPriority:NSLayoutPriorityDefaultLow forSubviewAtIndex:1];

    [contentView addSubview:self.splitView];
    [contentView addSubview:statusBar];

    [NSLayoutConstraint activateConstraints:@[
        [self.splitView.leadingAnchor constraintEqualToAnchor:contentView.leadingAnchor],
        [self.splitView.trailingAnchor constraintEqualToAnchor:contentView.trailingAnchor],
        [self.splitView.topAnchor constraintEqualToAnchor:contentView.topAnchor],
        [self.splitView.bottomAnchor constraintEqualToAnchor:statusBar.topAnchor],

        [statusBar.leadingAnchor constraintEqualToAnchor:contentView.leadingAnchor],
        [statusBar.trailingAnchor constraintEqualToAnchor:contentView.trailingAnchor],
        [statusBar.bottomAnchor constraintEqualToAnchor:contentView.bottomAnchor],
        [statusBar.heightAnchor constraintEqualToConstant:34.0],

        [self.statusLabel.leadingAnchor constraintEqualToAnchor:statusBar.leadingAnchor constant:12.0],
        [self.statusLabel.centerYAnchor constraintEqualToAnchor:statusBar.centerYAnchor],

        [self.contextLabel.leadingAnchor constraintEqualToAnchor:self.statusLabel.trailingAnchor constant:12.0],
        [self.contextLabel.centerYAnchor constraintEqualToAnchor:statusBar.centerYAnchor],
        [self.contextLabel.widthAnchor constraintLessThanOrEqualToConstant:220.0],

        [self.commandButton.trailingAnchor constraintEqualToAnchor:statusBar.trailingAnchor constant:-12.0],
        [self.commandButton.centerYAnchor constraintEqualToAnchor:statusBar.centerYAnchor],

        [self.commandField.trailingAnchor constraintEqualToAnchor:self.commandButton.leadingAnchor constant:-8.0],
        [self.commandField.centerYAnchor constraintEqualToAnchor:statusBar.centerYAnchor],
        [self.commandField.widthAnchor constraintGreaterThanOrEqualToConstant:320.0],
        [self.commandField.leadingAnchor constraintGreaterThanOrEqualToAnchor:self.contextLabel.trailingAnchor constant:16.0],
    ]];

    [contentView layoutSubtreeIfNeeded];
    [self positionDividerForCurrentWindowWidth];
    [self applyEditingModeUI];

    [NSApp activateIgnoringOtherApps:YES];
    [self.editorTextView setSelectedRange:NSMakeRange(0, 0)];
    [self.editorTextView scrollRangeToVisible:NSMakeRange(0, 0)];
    [self updateWindowTitle];
}

- (CGFloat)splitView:(NSSplitView *)splitView constrainMinCoordinate:(CGFloat)proposedMinimumPosition ofSubviewAt:(NSInteger)dividerIndex {
    (void)splitView;
    (void)dividerIndex;
    return 320.0;
}

- (CGFloat)splitView:(NSSplitView *)splitView constrainMaxCoordinate:(CGFloat)proposedMaximumPosition ofSubviewAt:(NSInteger)dividerIndex {
    (void)dividerIndex;
    return splitView.bounds.size.width - 320.0;
}

- (BOOL)splitView:(NSSplitView *)splitView canCollapseSubview:(NSView *)subview {
    (void)splitView;
    (void)subview;
    return NO;
}

- (void)windowDidResize:(NSNotification *)notification {
    (void)notification;
    [self positionDividerForCurrentWindowWidth];
}

- (void)windowDidBecomeKey:(NSNotification *)notification {
    if (notification.object != self.window) return;
    if (self.freeformModeEnabled) {
        if (self.window.firstResponder != self.freeformCanvasComponent) {
            [self.window makeFirstResponder:self.freeformCanvasComponent];
        }
        return;
    }
    if (self.window.firstResponder != self.editorTextView) {
        [self.window makeFirstResponder:self.editorTextView];
    }
}

- (void)positionDividerForCurrentWindowWidth {
    if (!self.splitView || self.splitView.subviews.count < 2) return;

    const CGFloat totalWidth = self.splitView.bounds.size.width;
    if (totalWidth <= 0.0) return;

    const CGFloat desiredLeftWidth = floor(totalWidth * 0.64);
    const CGFloat clampedLeftWidth = fmax(320.0, fmin(desiredLeftWidth, totalWidth - 320.0));
    [self.splitView setPosition:clampedLeftWidth ofDividerAtIndex:0];
}

- (NSView *)wrappedPaneWithTitle:(NSString *)title subtitle:(NSString *)subtitle bodyView:(NSView *)bodyView dark:(BOOL)dark titleLabel:(NSTextField * __strong *)outTitleLabel subtitleLabel:(NSTextField * __strong *)outSubtitleLabel {
    NSView *container = [[NSView alloc] initWithFrame:NSZeroRect];
    container.translatesAutoresizingMaskIntoConstraints = YES;
    container.wantsLayer = YES;
    container.layer.backgroundColor = (dark ? [NSColor colorWithRed:0.10 green:0.11 blue:0.13 alpha:1.0] : [NSColor colorWithRed:0.96 green:0.97 blue:0.98 alpha:1.0]).CGColor;
    if (dark) {
        NSAppearance *appearance = [self darkInspectorAppearance];
        container.appearance = appearance;
        bodyView.appearance = appearance;
    }

    NSTextField *titleLabel = [NSTextField labelWithString:title];
    titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    titleLabel.font = [NSFont systemFontOfSize:13.0 weight:NSFontWeightSemibold];
    titleLabel.textColor = dark ? [NSColor colorWithRed:0.95 green:0.96 blue:0.98 alpha:1.0] : [NSColor colorWithRed:0.18 green:0.20 blue:0.24 alpha:1.0];

    NSTextField *subtitleLabel = [NSTextField labelWithString:subtitle];
    subtitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    subtitleLabel.font = [NSFont systemFontOfSize:11.0 weight:NSFontWeightRegular];
    subtitleLabel.textColor = dark ? [NSColor colorWithRed:0.62 green:0.65 blue:0.70 alpha:1.0] : [NSColor colorWithRed:0.42 green:0.45 blue:0.50 alpha:1.0];

    if (outTitleLabel) *outTitleLabel = titleLabel;
    if (outSubtitleLabel) *outSubtitleLabel = subtitleLabel;

    NSBox *separator = [[NSBox alloc] initWithFrame:NSZeroRect];
    separator.translatesAutoresizingMaskIntoConstraints = NO;
    separator.boxType = NSBoxSeparator;

    [container addSubview:titleLabel];
    [container addSubview:subtitleLabel];
    [container addSubview:separator];
    [container addSubview:bodyView];

    [NSLayoutConstraint activateConstraints:@[
        [titleLabel.leadingAnchor constraintEqualToAnchor:container.leadingAnchor constant:14.0],
        [titleLabel.topAnchor constraintEqualToAnchor:container.topAnchor constant:12.0],

        [subtitleLabel.leadingAnchor constraintEqualToAnchor:titleLabel.leadingAnchor],
        [subtitleLabel.topAnchor constraintEqualToAnchor:titleLabel.bottomAnchor constant:2.0],

        [separator.leadingAnchor constraintEqualToAnchor:container.leadingAnchor],
        [separator.trailingAnchor constraintEqualToAnchor:container.trailingAnchor],
        [separator.topAnchor constraintEqualToAnchor:subtitleLabel.bottomAnchor constant:10.0],

        [bodyView.leadingAnchor constraintEqualToAnchor:container.leadingAnchor],
        [bodyView.trailingAnchor constraintEqualToAnchor:container.trailingAnchor],
        [bodyView.topAnchor constraintEqualToAnchor:separator.bottomAnchor],
        [bodyView.bottomAnchor constraintEqualToAnchor:container.bottomAnchor],
    ]];

    return container;
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender {
    (void)sender;
    return YES;
}

- (NSApplicationTerminateReply)applicationShouldTerminate:(NSApplication *)sender {
    (void)sender;
    if (!self.window.documentEdited) {
        return NSTerminateNow;
    }

    [self promptToSaveIfNeededThen:^(BOOL shouldContinue) {
        [NSApp replyToApplicationShouldTerminate:shouldContinue];
    }];
    return NSTerminateLater;
}

- (BOOL)windowShouldClose:(id)sender {
    if (sender != self.window || !self.window.documentEdited) {
        return YES;
    }

    [self promptToSaveIfNeededThen:^(BOOL shouldContinue) {
        if (shouldContinue) {
            [self.window setDocumentEdited:NO];
            [self.window close];
        }
    }];
    return NO;
}

@end

int merrow_studio_main(int argc, const char *argv[]) {
    (void)argc;
    (void)argv;

    @autoreleasepool {
        NSApplication *app = [NSApplication sharedApplication];
        MerrowStudioAppDelegate *delegate = [[MerrowStudioAppDelegate alloc] init];
        [app setActivationPolicy:NSApplicationActivationPolicyRegular];
        [app setDelegate:delegate];
        [app run];
    }

    return 0;
}